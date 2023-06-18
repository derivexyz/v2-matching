// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import {Matching} from "../Matching.sol";

abstract contract BaseModule is IMatchingModule {
  Matching public immutable matching;
  ISubAccounts public immutable accounts;

  mapping(address owner => mapping(uint nonce => bool used)) public usedNonces;

  constructor(Matching _matching) {
    matching = _matching;
    accounts = _matching.accounts();
  }

  function _returnAccounts(VerifiedOrder[] memory orders, uint[] memory newAccIds) internal {
    for (uint i = 0; i < orders.length; ++i) {
      if (orders[i].accountId == 0) continue;
      accounts.transferFrom(address(this), address(matching), orders[i].accountId);
    }
    for (uint i = 0; i < newAccIds.length; ++i) {
      accounts.transferFrom(address(this), address(matching), newAccIds[i]);
    }
  }

  function _checkAndInvalidateNonce(address owner, uint nonce) internal {
    require(!usedNonces[owner][nonce], "nonce already used");
    usedNonces[owner][nonce] = true;
  }

  modifier onlyMatching() {
    require(msg.sender == address(matching), "only matching");
    _;
  }
}
