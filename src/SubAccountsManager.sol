// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Inherited
import {Ownable2Step, Ownable} from "openzeppelin/access/Ownable2Step.sol";
import {ISubAccountsManager} from "./interfaces/ISubAccountsManager.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";

/**
 * @title SubAccountsManager
 * @dev Handle deposits, escape hatches for subAccounts. Users need to deposit their subAccount NFTs to use the Matching contract
 */
contract SubAccountsManager is ISubAccountsManager, Ownable2Step {
  ///@dev Cooldown seconds a user must wait before withdrawing their account
  uint public constant WITHDRAW_COOLDOWN = 30 minutes;

  ///@dev Accounts contract address
  ISubAccounts public immutable subAccounts;

  ///@dev Mapping of accountId to address
  mapping(uint => address) public subAccountToOwner;

  ///@dev Mapping of account to withdraw cooldown start time
  mapping(uint => uint) public withdrawTimestamp;

  constructor(ISubAccounts _subAccounts) Ownable(msg.sender) {
    subAccounts = _subAccounts;
  }

  /**
   * @notice Allows user to open an account by creating a new subAccount NFT.
   * @param manager The address of the manager for the new subAccount
   */
  function createSubAccount(IManager manager) external returns (uint accountId) {
    accountId = subAccounts.createAccount(address(this), manager);
    subAccountToOwner[accountId] = msg.sender;

    emit DepositedSubAccount(accountId, msg.sender);
  }

  /**
   * @notice Allows user to open an account by transferring their account NFT to this contract.
   * @dev User must approve contract first.
   * @param accountId The users' accountId
   */
  function depositSubAccount(uint accountId) external {
    subAccounts.transferFrom(msg.sender, address(this), accountId);
    subAccountToOwner[accountId] = msg.sender;

    emit DepositedSubAccount(accountId, msg.sender);
  }

  /**
   * @notice Allows user to open an account for another user by transferring subAccount NFT.
   * @dev User must approve contract first
   * @param accountId subAccount id to transfer
   * @param recipient recipient address
   */
  function depositSubAccountFor(uint accountId, address recipient) external {
    subAccounts.transferFrom(msg.sender, address(this), accountId);
    subAccountToOwner[accountId] = recipient;

    emit DepositedSubAccount(accountId, recipient);
  }

  /**
   * @notice Activates the cooldown period to withdraw account.
   */
  function requestWithdrawAccount(uint accountId) external {
    if (subAccountToOwner[accountId] != msg.sender) revert SAM_NotOwnerAddress();
    if (withdrawTimestamp[accountId] != 0) revert SAM_AlreadyRequestedWithdraw();

    withdrawTimestamp[accountId] = block.timestamp;

    emit WithdrawAccountCooldown(accountId, msg.sender);
  }

  /**
   * @notice Allows a user to complete their exit from the Matching system.
   * Can be called by anyone on withdrawable accounts.
   * @dev User must have previously called `requestWithdrawAccount()` and waited for the cooldown to elapse.
   * @param accountId The users' accountId
   */
  function completeWithdrawAccount(uint accountId) external {
    if (withdrawTimestamp[accountId] == 0) revert SAM_CooldownNotStarted();
    if (withdrawTimestamp[accountId] + WITHDRAW_COOLDOWN > block.timestamp) revert SAM_CooldownNotElapsed();

    subAccounts.transferFrom(address(this), subAccountToOwner[accountId], accountId);

    delete withdrawTimestamp[accountId];
    delete subAccountToOwner[accountId];

    emit WithdrewSubAccount(accountId);
  }
}
