// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {StandardManager} from "v2-core/src/risk-managers/StandardManager.sol";
import {PMRM, IPMRM} from "v2-core/src/risk-managers/PMRM.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {BaseModule} from "../modules/BaseModule.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

import {BaseTSA} from "./BaseTSA.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";

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
    bytes32 hash = matching.getActionHash(action);
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

  function _isValidSignature(bytes32 _hash, bytes memory _signature) internal view virtual returns (bool) {
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
