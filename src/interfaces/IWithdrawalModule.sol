// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";

interface IWithdrawalModule is IBaseModule {
  struct WithdrawalData {
    address asset;
    uint assetAmount;
  }

  error WM_InvalidWithdrawalOrderLength();
  error WM_InvalidFromAccount();
}
