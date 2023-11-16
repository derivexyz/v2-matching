// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";

interface IWithdrawalModule is IBaseModule {
  struct WithdrawalData {
    address asset;
    uint assetAmount;
  }

  error WM_InvalidWithdrawalActionLength();
  error WM_InvalidFromAccount();
}
