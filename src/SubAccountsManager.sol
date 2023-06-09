// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "openzeppelin/access/Ownable2Step.sol";
import "v2-core/src/SubAccounts.sol";
import "./interfaces/IMatcher.sol";

// Handle subAccounts, deposits, escape hatches etc.
contract SubAccountsManager is Ownable2Step {
  ///@dev Cooldown seconds a user must wait before withdrawing their account
  uint public withdrawAccountCooldown;

  ///@dev Cooldown seconds a user must wait before deregister
  uint deregisterKeyCooldown;

  ///@dev Accounts contract address
  ISubAccounts public immutable accounts;

  ///@dev Mapping of accountId to address
  mapping(uint => address) public accountToOwner;

  ///@dev Mapping of signer address -> owner address -> expiry
  mapping(address => mapping(address => uint)) public sessionKeys; // Allows other addresses to trade on behalf of others

  ///@dev Mapping of owner to account withdraw cooldown start time
  mapping(address => uint) public withdrawAccountCooldownMapping;

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice Set which address can submit trades.
   */
  function setSubAccounts(ISubAccounts _accounts) external onlyOwner {
    accounts = _accounts;

    emit SubAccountsSet(address(_accounts));
  }

  ///////////////////////
  //  Account actions  //
  ///////////////////////

  /**
   * @notice Allows user to open an account by transferring their account NFT to this contract.
   * @dev User must approve contract first.
   * @param accountId The users' accountId
   */
  function openCLOBAccount(uint accountId) external {
    accounts.transferFrom(msg.sender, address(this), accountId);
    accountToOwner[accountId] = msg.sender;

    emit OpenedCLOBAccount(accountId);
  }

  /**
   * @notice Activates the cooldown period to withdraw account.
   */
  function requestCloseCLOBAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
    withdrawAccountCooldownMapping[msg.sender] = block.timestamp;
    emit WithdrawAccountCooldown(msg.sender);
  }

  /**
   * @notice Allows user to close their account by transferring their account NFT back.
   * @dev User must have previously called `requestCloseCLOBAccount()` and waited for the cooldown to elapse.
   * @param accountId The users' accountId
   */
  function completeCloseCLOBAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
    if (withdrawAccountCooldownMapping[msg.sender] + (withdrawAccountCooldown) > block.timestamp) {
      revert M_CooldownNotElapsed(
        withdrawAccountCooldownMapping[msg.sender] + (withdrawAccountCooldown) - block.timestamp
      );
    }

    accounts.transferFrom(address(this), msg.sender, accountId);
    withdrawAccountCooldownMapping[msg.sender] = 0;
    delete accountToOwner[accountId];

    emit ClosedCLOBAccount(accountId);
  }

  // todo mint account and transfer

  ////////////////////
  //  Session Keys  //
  ////////////////////

  /**
   * @notice Allows owner to register the public address associated with their session key to their accountId.
   * @dev Registered address gains owner address permission to the subAccount until expiry.
   * @param expiry When the access to the owner address expires
   */
  function registerSessionKey(address toAllow, uint expiry) external {
    sessionKeys[toAllow][msg.sender] = expiry;

    emit SessionKeyRegistered(msg.sender, toAllow);
  }

  /**
   * @notice Allows owner to deregister a session key from their account.
   * @dev Expires the sessionKey after the cooldown.
   */
  function requestDeregisterSessionKey(address sessionKey) external {
    // Ensure the session key has not expired
    if (sessionKeys[sessionKey][msg.sender] < block.timestamp) revert M_SessionKeyInvalid(sessionKey);

    sessionKeys[sessionKey][msg.sender] = block.timestamp + deregisterKeyCooldown;
    emit SessionKeyCooldown(msg.sender, sessionKey);
  }

  // function verifyOwner()

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when SubAccounts contract is set.
   */
  event SubAccountsSet(address accounts);

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event OpenedCLOBAccount(uint accountId);

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event ClosedCLOBAccount(uint accountId);

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
  error M_NotOwnerAddress(address sender, address owner);
  error M_NotTokenOwner(uint accountId, address tokenOwner);
  error M_CooldownNotElapsed(uint secondsLeft);
  error M_SessionKeyInvalid(address sessionKeyPublicAddress);
  error M_ArrayLengthMismatch(uint length1, uint length2);
}
