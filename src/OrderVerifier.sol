// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

// Libraries
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

// Inherited
import "openzeppelin/utils/cryptography/EIP712.sol";
import {SubAccountsManager} from "./SubAccountsManager.sol";
import {IOrderVerifier} from "./interfaces/IOrderVerifier.sol";

// Interfaces
import {IMatchingModule} from "./interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";


contract OrderVerifier is IOrderVerifier, SubAccountsManager, EIP712 {

  bytes32 public constant ORDER_TYPEHASH = keccak256("SignedOrder(uint256,uint256,address,bytes,uint256,address)");

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
  function registerSessionKey(address toAllow, uint expiry) external {
    sessionKeys[toAllow][msg.sender] = expiry;

    emit SessionKeyRegistered(msg.sender, toAllow);
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
   * @param signer The address that signed the order
   * @param accIdOwner the original owner of the subaccount stored by matching contract
   * @param owner specified owner in the order
   */
  function _verifySignerPermission(address signer, address accIdOwner, address owner) internal view {
    if (accIdOwner != address(0) && accIdOwner != owner) revert OV_InvalidOrderOwner();

    if (signer != owner && sessionKeys[signer][owner] < block.timestamp) {
      revert OV_SignerNotOwnerOrSessionKeyExpired();
    }
  }

  /////////////////////////////
  // Signed message checking //
  /////////////////////////////

  function _verifyOrder(SignedOrder memory order) internal view returns (IMatchingModule.VerifiedOrder memory) {
    // Repeated nonces are fine; their uniqueness will be handled by modules
    if (block.timestamp > order.expiry) revert OV_OrderExpired();

    _verifySignerPermission(order.signer, subAccountToOwner[order.accountId], order.owner);

    _verifySignature(order.signer, _getOrderHash(order), order.signature);

    return IMatchingModule.VerifiedOrder({
      accountId: order.accountId,
      owner: order.owner,
      module: order.module,
      data: order.data,
      nonce: order.nonce
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

  function getOrderHash(SignedOrder memory order) external pure returns (bytes32) {
    return _getOrderHash(order);
  }

  function _getOrderHash(SignedOrder memory order) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ORDER_TYPEHASH, order.accountId, order.nonce, address(order.module), order.data, order.expiry, order.signer
      )
    );
  }
}
