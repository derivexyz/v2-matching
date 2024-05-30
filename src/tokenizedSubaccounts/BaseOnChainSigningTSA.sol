// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "./BaseTSA.sol";

import "forge-std/console2.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

/// @title BaseOnChainSigningTSA
/// @dev Prices shares in USD, but accepts baseAsset as deposit. Vault intended to try remain delta neutral.
abstract contract BaseOnChainSigningTSA is BaseTSA {
  // bytes4(keccak256("isValidSignature(bytes32,bytes)")
  bytes4 internal constant MAGICVALUE = 0x1626ba7e;

  struct BaseSigningTSAStorage {
    bool signaturesDisabled;
    mapping(address => bool) signers;
    mapping(bytes32 => bool) signedData;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.BaseOnChainSigningTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant BaseSigningTSAStorageLocation = 0x9f245ffe322048fbfccbbec5cbd54060b7369b5a75ba744e76b5291974322100;

  function _getBaseSigningTSAStorage() private pure returns (BaseSigningTSAStorage storage $) {
    assembly {
      $.slot := BaseSigningTSAStorageLocation
    }
  }

  ///////////
  // Admin //
  ///////////
  function setSigner(address signer, bool isSigner) external onlyOwner {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    $.signers[signer] = isSigner;
  }

  function setSignaturesEnabled(bool enabled) external onlyOwner {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    $.signaturesDisabled = enabled;
  }

  /////////////
  // Signing //
  /////////////
  function signActionData(IMatching.Action memory action) external virtual onlySigner {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    bytes32 hash = ECDSA.toTypedDataHash(
      tsaAddresses.matching.domainSeparator(),
      tsaAddresses.matching.getActionHash(action)
    );

    require(action.signer == address(this), "BaseOnChainSigningTSA: action.signer must be TSA");

    _verifyAction(action, hash);
    $.signedData[hash] = true;
  }

  function revokeActionSignature(IMatching.Action memory action) external virtual onlySigner {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    bytes32 hash = ECDSA.toTypedDataHash(
      tsaAddresses.matching.domainSeparator(),
      tsaAddresses.matching.getActionHash(action)
    );

    _revokeSignature(hash);
  }

  function revokeSignature(bytes32 hash) external virtual onlySigner {
    _revokeSignature(hash);
  }

  function _revokeSignature(bytes32 hash) internal virtual {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    $.signedData[hash] = false;
  }

  function _verifyAction(IMatching.Action memory action, bytes32 actionHash) internal virtual;

  ////////////////
  // Validation //
  ////////////////
  function isValidSignature(bytes32 _hash, bytes memory _signature)
    external
    view
    checkBlocked
    returns (bytes4 magicValue)
  {
    if (_isValidSignature(_hash, _signature)) {
      return MAGICVALUE;
    }
    return bytes4(0);
  }

  function _isValidSignature(bytes32 _hash, bytes memory /* _signature */ ) internal view virtual returns (bool) {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    return !$.signaturesDisabled && $.signedData[_hash];
  }

  ///////////////
  // Modifiers //
  ///////////////
  modifier onlySigner() {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    require($.signers[msg.sender], "BaseOnChainSigningTSA: Not a signer");
    _;
  }
}
