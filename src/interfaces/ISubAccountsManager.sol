// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";

interface ISubAccountsManager {
  function WITHDRAW_COOLDOWN() external view returns (uint);

  function subAccounts() external view returns (ISubAccounts);

  function subAccountToOwner(uint) external view returns (address);

  function withdrawTimestamp(uint) external view returns (uint);

  function createSubAccount(IManager manager) external returns (uint accountId);

  /**
   * @notice Allows user to open an account by transferring their account NFT to this contract.
   * @dev User must approve contract first.
   * @param accountId The users' accountId
   */
  function depositSubAccount(uint accountId) external;

  /**
   * @notice Allows user to open an account for any address by transferring their own account NFT to this contract.
   */
  function depositSubAccountFor(uint accountId, address recipient) external;

  /**
   * @notice Activates the cooldown period to withdraw account.
   */
  function requestWithdrawAccount(uint accountId) external;

  /**
   * @notice Allows a user to complete their exit from the Matching system.
   * Can be called by anyone on withdrawable accounts.
   * @dev User must have previously called `requestWithdrawAccount()` and waited for the cooldown to elapse.
   * @param accountId The users' accountId
   */
  function completeWithdrawAccount(uint accountId) external;

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event DepositedSubAccount(uint indexed accountId, address indexed owner);

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event WithdrewSubAccount(uint indexed accountId);

  /**
   * @dev Emitted when a user requests account withdrawal and begins the cooldown
   */
  event WithdrawAccountCooldown(uint indexed accountId, address user);

  ////////////
  // Errors //
  ////////////
  error SAM_NotOwnerAddress();
  error SAM_CooldownNotElapsed();
}
