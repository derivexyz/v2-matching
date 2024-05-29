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

  bool public signingEnabled = true;
  mapping(address => bool) public signers;
  mapping(bytes32 hash => bool) public signedData;

  constructor(BaseTSA.BaseTSAInitParams memory initParams) BaseTSA(initParams) {}

  ///////////
  // Admin //
  ///////////
  function setSigner(address signer, bool isSigner) external onlyOwner {
    signers[signer] = isSigner;
  }

  function setSignaturesEnabled(bool enabled) external onlyOwner {
    signingEnabled = enabled;
  }

  /////////////
  // Signing //
  /////////////
  function signActionData(IMatching.Action memory action) external virtual onlySigner {
    bytes32 hash = ECDSA.toTypedDataHash(matching.domainSeparator(), matching.getActionHash(action));
    require(action.signer == address(this), "BaseOnChainSigningTSA: action.signer must be TSA");
    _verifyAction(action, hash);
    signedData[hash] = true;
  }

  function revokeActionSignature(IMatching.Action memory action) external virtual onlySigner {
    bytes32 hash = matching.getActionHash(action);
    signedData[hash] = false;
  }

  function revokeSignature(bytes32 hash) external virtual onlySigner {
    signedData[hash] = false;
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
    return signingEnabled && signedData[_hash];
  }

  ///////////////
  // Modifiers //
  ///////////////
  modifier onlySigner() {
    require(signers[msg.sender], "BaseOnChainSigningTSA: Not a signer");
    _;
  }
}
