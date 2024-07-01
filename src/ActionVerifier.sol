// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Libraries
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

// Inherited
import "openzeppelin/utils/cryptography/EIP712.sol";
import {SubAccountsManager} from "./SubAccountsManager.sol";
import {IActionVerifier} from "./interfaces/IActionVerifier.sol";

// Interfaces
import {IMatchingModule} from "./interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

/**
 * @title ActionVerifier
 * @dev Handles signature verification and session keys for actions
 */
contract ActionVerifier is IActionVerifier, SubAccountsManager, EIP712 {
  bytes32 public constant ACTION_TYPEHASH = keccak256(
    "Action(uint256 subaccountId,uint256 nonce,address module,bytes data,uint256 expiry,address owner,address signer)"
  );

  uint public constant DEREGISTER_KEY_COOLDOWN = 10 minutes;

  /// @notice Allows other addresses to trade on behalf of users
  /// @dev Mapping of signer address -> owner address -> expiry
  mapping(address signer => mapping(address owner => uint)) public sessionKeys;

  constructor(ISubAccounts _accounts) SubAccountsManager(_accounts) EIP712("Matching", "1.0") {}

  /**
   * @notice Allows owners to a register session key to authorize actions for deposited subAccounts.
   * @dev Registered address gains owner address permission to the subAccount until expiry.
   * @param expiry When the access to the owner address expires
   */
  function registerSessionKey(address sessionKey, uint expiry) external {
    if (expiry <= sessionKeys[sessionKey][msg.sender]) revert OV_NeedDeregister();

    sessionKeys[sessionKey][msg.sender] = expiry;

    emit SessionKeyRegistered(msg.sender, sessionKey, expiry);
  }

  /**
   * @notice Allows owner to deregister a session key.
   * @dev Expires the sessionKey after the cooldown.
   */
  function deregisterSessionKey(address sessionKey) external {
    // Ensure the session key has not expired
    if (sessionKeys[sessionKey][msg.sender] < block.timestamp) revert OV_SessionKeyInvalid();

    sessionKeys[sessionKey][msg.sender] = block.timestamp + DEREGISTER_KEY_COOLDOWN;
    emit SessionKeyCooldown(msg.sender, sessionKey);
  }

  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  function getActionHash(Action memory action) external pure returns (bytes32) {
    return _getActionHash(action);
  }

  /////////////////////////////
  //    Internal Functions   //
  /////////////////////////////

  /**
   * @notice Verify that the signer is the owner or has been permitted to trade on behalf of the owner
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

  /**
   * @notice Verify that the action is properly authorized by the original owner.
   * @param action The action to verify.
   * @param signature The signature signed by the owner or registered sessionKey.
   */
  function _verifyAction(Action memory action, bytes memory signature)
    internal
    view
    returns (IMatchingModule.VerifiedAction memory)
  {
    // Repeated nonces are fine; their uniqueness will be handled by modules
    if (block.timestamp > action.expiry) revert OV_ActionExpired();

    _verifySignerPermission(action.signer, subAccountToOwner[action.subaccountId], action.owner);

    _verifySignature(action.signer, _getActionHash(action), signature);

    return IMatchingModule.VerifiedAction({
      subaccountId: action.subaccountId,
      owner: action.owner,
      module: action.module,
      data: action.data,
      nonce: action.nonce
    });
  }

  /**
   * @notice Verify that the signature is valid.
   * @dev if signer is a contract, use ERC1271 to verify the signature
   */
  function _verifySignature(address signer, bytes32 structuredHash, bytes memory signature) internal view {
    if (!SignatureChecker.isValidSignatureNow(signer, _hashTypedDataV4(structuredHash), signature)) {
      revert OV_InvalidSignature();
    }
  }

  function _getActionHash(Action memory action) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ACTION_TYPEHASH,
        action.subaccountId,
        action.nonce,
        address(action.module),
        keccak256(action.data),
        action.expiry,
        action.owner,
        action.signer
      )
    );
  }
}
