// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "./IMatchingModule.sol";
import {IMatching} from "./IMatching.sol";

interface IBaseModule is IMatchingModule {
  function matching() external view returns (IMatching);
  function subAccounts() external view returns (ISubAccounts);

  event NonceUsed(address indexed owner, uint nonce);

  error BM_NonceAlreadyUsed();
  error BM_OnlyMatching();
}
