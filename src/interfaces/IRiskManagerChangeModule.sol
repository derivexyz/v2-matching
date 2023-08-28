// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";

interface IRiskManagerChangeModule is IBaseModule {
  error RMCM_InvalidActionLength();
}
