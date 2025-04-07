// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "../../../src/tokenizedSubaccounts/LevBasisTSA.sol";

contract PublicLBTSA is LeveragedBasisTSA {
  function verifyTradeDelta(
    ITradeModule.TradeData memory tradeData,
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars,
    bool isWithdrawal
  ) public view {
    int amtDelta = tradeData.isBid ? tradeData.desiredAmount : -tradeData.desiredAmount;
    _verifyTradeDelta(tradeHelperVars, amtDelta, isWithdrawal);
  }

  function verifyTradeLeverage(
    ITradeModule.TradeData memory tradeData,
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars,
    bool isWithdrawal
  ) public view {
    int amtDelta = tradeData.isBid ? tradeData.desiredAmount : -tradeData.desiredAmount;
    _verifyTradeLeverage(tradeHelperVars, amtDelta, isWithdrawal);
  }

  // Note: NOT view, so state is updated on each call
  function verifyTradeMarkLossEma(
    int currentEMA,
    uint lastTs,
    ITradeModule.TradeData memory tradeData,
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars
  ) public {
    LBTSAStorage storage $ = _getLBTSAStorage();
    $.markLossEma = currentEMA;
    $.markLossLastTs = lastTs;

    _verifyEmaMarkLoss(tradeData, tradeHelperVars);
  }
}
