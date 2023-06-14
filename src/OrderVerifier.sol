// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

import "v2-core/interfaces/ISubAccounts.sol";
import "./interfaces/IMatchingModule.sol";

import "./SubAccountsManager.sol";

contract OrderVerifier is SubAccountsManager, EIP712 {
  // (accountID, signer, nonce) must be unique
  struct SignedOrder {
    uint accountId;
    uint nonce;
    IMatchingModule matcher;
    bytes data;
    uint expiry;
    address signer;
    bytes signature;
  }

  bytes32 public constant ORDER_TYPEHASH = keccak256("SignedOrder(uint256,uint256,address,bytes,uint256,address)");
  uint public constant DERIGISTER_KEY_COOLDOWN = 10 minutes;

  ///@dev Mapping of signer address -> owner address -> expiry
  mapping(address => mapping(address => uint)) public sessionKeys; // Allows other addresses to trade on behalf of others

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
  function requestDeregisterSessionKey(address sessionKey) external {
    // Ensure the session key has not expired
    if (sessionKeys[sessionKey][msg.sender] < block.timestamp) revert M_SessionKeyInvalid(sessionKey);

    sessionKeys[sessionKey][msg.sender] = block.timestamp + DERIGISTER_KEY_COOLDOWN;
    emit SessionKeyCooldown(msg.sender, sessionKey);
  }

  function _verifySignerPermission(address signer, address owner) internal view {
    if (signer != owner && sessionKeys[signer][owner] < block.timestamp) {
      revert("signer not permitted, or session key expired");
    }
  }

  /////////////////////////////
  // Signed message checking //
  /////////////////////////////

  function _verifyOrder(SignedOrder memory order, IMatchingModule matcher)
    internal
    returns (IMatchingModule.VerifiedOrder memory)
  {
    // Repeated nonces are fine; their uniqueness will be handled by matchers (and any order limits etc for reused orders)
    if (order.expiry > block.timestamp) revert("Order expired");
    _verifySignerPermission(order.signer, accountToOwner[order.accountId]);
    _verifySignature(order.signer, _getOrderHash(order), order.signature);

    return IMatchingModule.VerifiedOrder({
      accountId: order.accountId,
      owner: address(0),
      matcher: order.matcher,
      data: order.data,
      nonce: order.nonce
    });
  }

  function _verifySignature(address signer, bytes32 structuredHash, bytes memory signature)
    internal
    view
    returns (bool)
  {
    return SignatureChecker.isValidSignatureNow(signer, _hashTypedDataV4(structuredHash), signature);
  }

  /////////////
  // Hashing //
  /////////////

  function _getOrderHash(SignedOrder memory order) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ORDER_TYPEHASH, order.accountId, order.nonce, address(order.matcher), order.data, order.expiry, order.signer
      )
    );
  }
}
