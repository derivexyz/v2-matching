// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import "./IBaseModule.sol";

interface ILiquidateModule is IBaseModule {
  struct LiquidationData {
    uint liquidatedAccountId;
    uint cashTransfer;
    uint percentOfAcc;
    int priceLimit;
    uint lastSeenTradeId;
    bool mergeAccount;
  }

  error LM_InvalidFromAccount();
  error LM_InvalidLiquidateActionLength();
}
