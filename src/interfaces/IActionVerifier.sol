// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMatchingModule} from "./IMatchingModule.sol";
import {ISubAccountsManager} from "./ISubAccountsManager.sol";

interface IActionVerifier is ISubAccountsManager {
  // (accountID, signer, nonce) must be unique
  struct Action {
    uint accountId;
    uint nonce;
    IMatchingModule module;
    bytes data;
    uint expiry;
    address owner;
    address signer;
    bytes signature;
  }

  function ACTION_TYPEHASH() external pure returns (bytes32);
  function DEREGISTER_KEY_COOLDOWN() external pure returns (uint);

  /// @notice Allows other addresses to trade on behalf of others
  /// @dev Mapping of signer address -> owner address -> expiry
  function sessionKeys(address signer, address owner) external view returns (uint expiry);

  function registerSessionKey(address toAllow, uint expiry) external;
  function deregisterSessionKey(address sessionKey) external;
  function domainSeparator() external view returns (bytes32);
  function getActionHash(Action memory action) external pure returns (bytes32);

  /**
   * @dev Emitted when a session key is registered to an owner account.
   */
  event SessionKeyRegistered(address owner, address sessionKey, uint expiry);

  /**
   * @dev Emitted when a user requests to deregister a session key.
   */
  event SessionKeyCooldown(address owner, address sessionKeyPublicAddress);

  /// @dev Emitted when user is trying to lower the expiry of a session key
  error OV_NeedDeregister();
  error OV_SessionKeyInvalid();
  error OV_ActionExpired();
  error OV_InvalidSignature();
  error OV_InvalidActionOwner();
  error OV_SignerNotOwnerOrSessionKeyExpired();
}
