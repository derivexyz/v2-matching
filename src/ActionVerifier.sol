// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

// Libraries
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

// Inherited
import "openzeppelin/utils/cryptography/EIP712.sol";
import {SubAccountsManager} from "./SubAccountsManager.sol";
import {IActionVerifier} from "./interfaces/IActionVerifier.sol";

// Interfaces
import {IMatchingModule} from "./interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

contract ActionVerifier is IActionVerifier, SubAccountsManager, EIP712 {
  bytes32 public constant ACTION_TYPEHASH = keccak256("SignedAction(uint256,uint256,address,bytes,uint256,address)");

  uint public constant DEREGISTER_KEY_COOLDOWN = 10 minutes;

  /// @notice Allows other addresses to trade on behalf of others
  /// @dev Mapping of signer address -> owner address -> expiry
  mapping(address signer => mapping(address owner => uint)) public sessionKeys;

  constructor(ISubAccounts _accounts) SubAccountsManager(_accounts) EIP712("Matching", "1.0") {}

  ////////////////////
  //  Session Keys  //
  ////////////////////

  /**
   * @notice Allows owner to register the public address associated with their session key to their accountId.
   * @dev Registered address gains owner address permission to the subAccount until expiry.
   * @param expiry When the access to the owner address expires
   */
  function registerSessionKey(address sessionKey, uint expiry) external {
    if (expiry <= sessionKeys[sessionKey][msg.sender]) revert OV_NeedDeregister();

    sessionKeys[sessionKey][msg.sender] = expiry;

    emit SessionKeyRegistered(msg.sender, sessionKey, expiry);
  }

  /**
   * @notice Allows owner to deregister a session key from their account.
   * @dev Expires the sessionKey after the cooldown.
   */
  function deregisterSessionKey(address sessionKey) external {
    // Ensure the session key has not expired
    if (sessionKeys[sessionKey][msg.sender] < block.timestamp) revert OV_SessionKeyInvalid();

    sessionKeys[sessionKey][msg.sender] = block.timestamp + DEREGISTER_KEY_COOLDOWN;
    emit SessionKeyCooldown(msg.sender, sessionKey);
  }

  /**
   * @notice verify that the signer is the owner or has been permitted to trade on behalf of the owner
   * @param signer The address that signed the action
   * @param accIdOwner the original owner of the subaccount stored by matching contract
   * @param owner specified owner in the action
   */
  function _verifySignerPermission(address signer, address accIdOwner, address owner) internal view {
    if (accIdOwner != address(0) && accIdOwner != owner) revert OV_InvalidActionOwner();

    if (signer != owner && sessionKeys[signer][owner] < block.timestamp) {
      revert OV_SignerNotOwnerOrSessionKeyExpired();
    }
  }

  /////////////////////////////
  // Signed message checking //
  /////////////////////////////

  function _verifyAction(SignedAction memory action) internal view returns (IMatchingModule.VerifiedAction memory) {
    // Repeated nonces are fine; their uniqueness will be handled by modules
    if (block.timestamp > action.expiry) revert OV_ActionExpired();

    _verifySignerPermission(action.signer, subAccountToOwner[action.accountId], action.owner);

    _verifySignature(action.signer, _getActionHash(action), action.signature);

    return IMatchingModule.VerifiedAction({
      accountId: action.accountId,
      owner: action.owner,
      module: action.module,
      data: action.data,
      nonce: action.nonce
    });
  }

  function _verifySignature(address signer, bytes32 structuredHash, bytes memory signature) internal view {
    if (!SignatureChecker.isValidSignatureNow(signer, _hashTypedDataV4(structuredHash), signature)) {
      revert OV_InvalidSignature();
    }
  }

  /////////////
  // Hashing //
  /////////////

  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  function getActionHash(SignedAction memory action) external pure returns (bytes32) {
    return _getActionHash(action);
  }

  function _getActionHash(SignedAction memory action) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_TYPEHASH, action.accountId, action.nonce, address(action.module), action.data, action.expiry, action.signer
      )
    );
  }
}
