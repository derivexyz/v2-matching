// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Inherited
import {IBaseModule} from "../interfaces/IBaseModule.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatching} from "../interfaces/IMatching.sol";

abstract contract BaseModule is IBaseModule {
  IMatching public immutable matching;
  ISubAccounts public immutable subAccounts;

  mapping(address owner => mapping(uint nonce => bool used)) public usedNonces;

  constructor(IMatching _matching) {
    matching = _matching;
    subAccounts = _matching.subAccounts();
  }

  function _returnAccounts(VerifiedOrder[] memory orders, uint[] memory newAccIds) internal {
    for (uint i = 0; i < orders.length; ++i) {
      if (orders[i].accountId == 0) continue;
      if (subAccounts.ownerOf(orders[i].accountId) == address(matching)) continue;

      subAccounts.transferFrom(address(this), address(matching), orders[i].accountId);
    }
    for (uint i = 0; i < newAccIds.length; ++i) {
      subAccounts.transferFrom(address(this), address(matching), newAccIds[i]);
    }
  }

  function _checkAndInvalidateNonce(address owner, uint nonce) internal {
    if (usedNonces[owner][nonce]) revert BM_NonceAlreadyUsed();
    usedNonces[owner][nonce] = true;

    emit NonceUsed(owner, nonce);
  }

  ///////////////
  // Modifiers //
  ///////////////
  modifier onlyMatching() {
    if (msg.sender != address(matching)) revert BM_OnlyMatching();
    _;
  }
}
