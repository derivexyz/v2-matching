// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "openzeppelin/access/Ownable2Step.sol";
import "v2-core/src/interfaces/ISubAccounts.sol";
import "./interfaces/IMatchingModule.sol";

// Handle subAccounts, deposits, escape hatches etc.
contract SubAccountsManager is Ownable2Step {
  ///@dev Cooldown seconds a user must wait before withdrawing their account
  uint public constant WITHDRAW_COOLDOWN = 30 minutes;

  ///@dev Accounts contract address
  ISubAccounts public immutable accounts;

  ///@dev Mapping of accountId to address
  mapping(uint => address) public accountToOwner;

  ///@dev Mapping of account to withdraw cooldown start time
  mapping(uint => uint) public withdrawTimestamp;

  constructor(ISubAccounts _accounts) {
    accounts = _accounts;
  }

  ///////////////////////
  //  Account actions  //
  ///////////////////////

  /**
   * @notice Allows user to open an account by transferring their account NFT to this contract.
   * @dev User must approve contract first.
   * @param accountId The users' accountId
   */
  function depositSubAccount(uint accountId) external {
    accounts.transferFrom(msg.sender, address(this), accountId);
    accountToOwner[accountId] = msg.sender;

    emit DepositedSubAccount(accountId);
  }

  /**
   * @notice Activates the cooldown period to withdraw account.
   */
  function requestWithdrawAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress();
    withdrawTimestamp[accountId] = block.timestamp;
    emit WithdrawAccountCooldown(msg.sender);
  }

  /**
   * @notice Allows user to close their account by transferring their account NFT back.
   * @dev User must have previously called `requestWithdrawAccount()` and waited for the cooldown to elapse.
   * @param accountId The users' accountId
   */
  function completeWithdrawAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress();
    if (withdrawTimestamp[accountId] + WITHDRAW_COOLDOWN > block.timestamp) {
      revert M_CooldownNotElapsed(withdrawTimestamp[accountId] + WITHDRAW_COOLDOWN - block.timestamp);
    }

    accounts.transferFrom(address(this), msg.sender, accountId);
    delete withdrawTimestamp[accountId];
    delete accountToOwner[accountId];

    emit WithdrewSubAccount(accountId);
  }

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event DepositedSubAccount(uint accountId);

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event WithdrewSubAccount(uint accountId);

  /**
   * @dev Emitted when a session key is registered to an owner account.
   */
  event SessionKeyRegistered(address owner, address sessionKey);

  /**
   * @dev Emitted when a user requests account withdrawal and begins the cooldown
   */
  event WithdrawAccountCooldown(address user);

  /**
   * @dev Emitted when a user requests to deregister a session key.
   */
  event SessionKeyCooldown(address owner, address sessionKeyPublicAddress);

  ////////////
  // Errors //
  ////////////
  error M_NotOwnerAddress();
  
  error M_CooldownNotElapsed(uint secondsLeft);

}
