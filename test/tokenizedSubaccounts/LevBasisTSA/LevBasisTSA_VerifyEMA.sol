pragma solidity ^0.8.18;

import "../utils/LBTSATestUtils.sol";

contract LevBasisTSA_VerifyEMATests is LBTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLBTSA();
    setupLBTSA();

    _setMaxLossBounds(0.01e18, 0.01e18);
    _setEMAParams(0.000192541e18, 0.01e18);
    vm.warp(block.timestamp + 1_000 days);
  }

  // EMA No Loss Test
  // ----------------
  // Test that no loss occurs when trade price equals base price
  function test_ema_noLoss() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(10e18, 2000e18, 10e18, true);

    // trade is at the same price as base, so no loss should occur
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    _validateEMAValues(0, block.timestamp);

    // same for a sell order
    tradeData.isBid = false;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    _validateEMAValues(0, block.timestamp);

    // same for perp trades
    tradeHelperVars.isBaseTrade = false;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    _validateEMAValues(0, block.timestamp);

    // same for a buy order
    tradeData.isBid = true;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    _validateEMAValues(0, block.timestamp);
  }

  // EMA Loss Test
  // -------------
  // Test that a loss is recorded when trade price is less favorable than base price
  function test_ema_loss() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    // use perpPrice to determine the $ loss, for perps only, and basePrice (2000) will be used work out the TVL loss
    tradeHelperVars.perpPrice = 2020e18;

    ITradeModule.TradeData memory tradeData = _getTradeData(10e18, 2010e18, 10e18, true);

    // buying base for more than its worth.

    // paying 10 extra per base, so total loss of 100
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in base price, the loss is 100 / 2000 = 0.05 base. Dividing by 20 (base balance) gives 0.0025
    _validateEMAValues(0.0025e18, block.timestamp);

    // buying base for less than its worth.
    tradeData.limitPrice = 1990e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in base price, the loss is -100 / 2000 = -0.05 base. Dividing by 20 (base balance) gives -0.0025
    // "negative loss" because it is a gain
    _validateEMAValues(-0.0025e18, block.timestamp);

    // buying perp for more than its worth.
    tradeHelperVars.isBaseTrade = false;
    tradeData.limitPrice = 2030e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in perp price, the loss is 100 / 2000 = 0.05 base. Dividing by 20 (base balance) gives 0.0025
    _validateEMAValues(0.0025e18, block.timestamp);

    // buying perp for less than its worth.
    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in perp price, the loss is -100 / 2000 = -0.05 base. Dividing by 20 (base balance) gives -0.0025
    // "negative loss" because it is a gain
    _validateEMAValues(-0.0025e18, block.timestamp);

    // selling base for more than its worth.
    tradeHelperVars.isBaseTrade = true;
    tradeData.isBid = false;
    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in base price, the loss is 100 / 2000 = 0.05 base. Dividing by 20 (base balance) gives 0.0025
    _validateEMAValues(-0.0025e18, block.timestamp);

    // selling base for less than its worth.
    tradeData.limitPrice = 1990e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in base price, the loss is -100 / 2000 = -0.05 base. Dividing by 20 (base balance) gives -0.0025
    // "negative loss" because it is a gain
    _validateEMAValues(0.0025e18, block.timestamp);

    // selling perp for more than its worth.
    tradeHelperVars.isBaseTrade = false;
    tradeData.isBid = false;
    tradeData.limitPrice = 2030e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in perp price, the loss is 100 / 2000 = 0.05 base. Dividing by 20 (base balance) gives 0.0025
    _validateEMAValues(-0.0025e18, block.timestamp);

    // selling perp for less than its worth.
    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp - 500, tradeData, tradeHelperVars);
    // since loss is in perp price, the loss is -100 / 2000 = -0.05 base. Dividing by 20 (base balance) gives -0.0025
    // "negative loss" because it is a gain
    _validateEMAValues(0.0025e18, block.timestamp);
  }

  // EMA Decay Test
  // --------------
  // Test that EMA decays over time
  function test_ema_decay() public {
    // We do a trade of 0 to not affect the EMA, and test decay in isolation
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0, 2000e18, 0, true);

    // 0.0002 ~= 1hr half life (e^(-X * 3600) = 0.5)
    _setEMAParams(0.000192541e18, 0.01e18);

    lbtsa.verifyTradeMarkLossEma(0.1e18, block.timestamp - 1 hours, tradeData, tradeHelperVars);

    // an hour of decay halves it
    _validateEMAValuesClose(0.05e18, block.timestamp, 0.00005e18);

    // same for negative values
    lbtsa.verifyTradeMarkLossEma(-0.05e18, block.timestamp - 1 hours, tradeData, tradeHelperVars);
    _validateEMAValuesClose(-0.025e18, block.timestamp, 0.00005e18);

    // 2 hours of decay quarters it
    lbtsa.verifyTradeMarkLossEma(0.1e18, block.timestamp - 2 hours, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.025e18, block.timestamp, 0.00005e18);

    // ~25min of decay would reduce the ema by 25%
    lbtsa.verifyTradeMarkLossEma(0.1e18, block.timestamp - 25 minutes, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.075e18, block.timestamp, 0.005e18);

    // with a different decay factor, the half life is different
    _setEMAParams(0.00000802254e18, 0.01e18);
    lbtsa.verifyTradeMarkLossEma(0.1e18, block.timestamp - 1 days, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.05e18, block.timestamp, 0.00005e18);
  }

  // EMA Change Test
  // --------------------
  // Test that EMA changes when trades are made that result in a loss/gain
  function test_ema_change() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(10e18, 2000e18, 10e18, true);

    // start with a loss of 0.01, a trade that makes no loss/gain will not change the ema
    lbtsa.verifyTradeMarkLossEma(0.005e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.005e18, block.timestamp, 0.00005e18);

    // a trade that makes a loss will increase the ema
    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(0.005e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.0075e18, block.timestamp, 0.00005e18);

    // a trade that makes a gain will decrease the ema
    tradeData.limitPrice = 1990e18;
    lbtsa.verifyTradeMarkLossEma(0.005e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.0025e18, block.timestamp, 0.00005e18);

    // this also works if ema starts with a negative value
    tradeData.limitPrice = 2000e18;
    lbtsa.verifyTradeMarkLossEma(-0.005e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(-0.005e18, block.timestamp, 0.00005e18);

    // a trade that makes a gain will decrease the ema
    tradeData.limitPrice = 1990e18;
    lbtsa.verifyTradeMarkLossEma(-0.005e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(-0.0075e18, block.timestamp, 0.00005e18);

    // a trade that makes a loss will increase the ema
    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(-0.005e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(-0.0025e18, block.timestamp, 0.00005e18);

    // ema will both decay and then apply the change if time has passed since last update
    tradeData.limitPrice = 2000e18;
    lbtsa.verifyTradeMarkLossEma(-0.005e18, block.timestamp - 1 hours, tradeData, tradeHelperVars);
    _validateEMAValuesClose(-0.0025e18, block.timestamp, 0.00005e18);

    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(-0.005e18, block.timestamp - 1 hours, tradeData, tradeHelperVars);
    // decays to -0.0025, then reduced to 0
    _validateEMAValuesClose(0, block.timestamp, 0.00005e18);

    // a trade that makes a gain will reduce the ema further after decay
    tradeData.limitPrice = 1990e18;
    lbtsa.verifyTradeMarkLossEma(-0.005e18, block.timestamp - 1 hours, tradeData, tradeHelperVars);
    _validateEMAValuesClose(-0.005e18, block.timestamp, 0.00005e18);
  }

  // MartkLossEmaTarget tests
  // -------------------------
  // Test that the MarkLossEmaTarget is respected
  function test_ema_markLossEmaTarget() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(10e18, 2010e18, 10e18, true);

    // Start with EMA at 0
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp, tradeData, tradeHelperVars);
    // Loss should be 0.0025e18 (as calculated in previous test)
    _validateEMAValuesClose(0.0025e18, block.timestamp, 0.00005e18);

    // Trade that makes the total loss 1% of TVL, which is just within bounds is accepted
    lbtsa.verifyTradeMarkLossEma(0.0075e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.01e18, block.timestamp, 0.00005e18);

    // A trade that would make the total loss >1% of TVL is rejected
    vm.expectRevert(LeveragedBasisTSA.LBT_MarkLossTooHigh.selector);
    lbtsa.verifyTradeMarkLossEma(0.00750001e18, block.timestamp, tradeData, tradeHelperVars);

    // but if bounds are increased, it is accepted
    _setEMAParams(0.000192541e18, 0.012e18);
    lbtsa.verifyTradeMarkLossEma(0.00750001e18, block.timestamp, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.01000001e18, block.timestamp, 0.00005e18);

    // If a trade would "improve" EMA due to decay, it is rejected if final EMA is still too high
    _setEMAParams(0.000192541e18, 0.01e18);
    // we start at 0.02, decay goes to 0.01, then we make a loss of 0.002, so ema is 0.012.
    vm.expectRevert(LeveragedBasisTSA.LBT_MarkLossTooHigh.selector);
    lbtsa.verifyTradeMarkLossEma(0.02e18, block.timestamp - 1 hours, tradeData, tradeHelperVars);

    // but if we wait long enough, it is accepted
    lbtsa.verifyTradeMarkLossEma(0.02e18, block.timestamp - 2 hours, tradeData, tradeHelperVars);
    _validateEMAValuesClose(0.0075e18, block.timestamp, 0.00005e18);
  }

  // LossPerUnit tests
  // ------------------
  // Test that the loss per unit reverts as expected
  function test_ema_lossPerUnit() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(10e18, 2010e18, 10e18, true);

    // lossPerUnitBase is calculated as (loss / basePrice)
    // so for a 10e18 base trade, the loss per unit is 10e18 / 2000e18 = 0.005
    // this is accepted with default params
    tradeData.limitPrice = 2010e18;
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp, tradeData, tradeHelperVars);

    // but rejected if the maxBaseLossPerBase is reduced
    _setMaxLossBounds(0.004e18, 0.01e18);
    vm.expectRevert(LeveragedBasisTSA.LBT_InvalidGainPerUnit.selector);
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp, tradeData, tradeHelperVars);

    // accepted if the maxBaseLossPerBase is exactly met
    _setMaxLossBounds(0.005e18, 0.01e18);
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp, tradeData, tradeHelperVars);

    // same for perp trades
    tradeHelperVars.isBaseTrade = false;
    tradeData.limitPrice = 2010e18;
    _setMaxLossBounds(0.01e18, 0.004e18);
    vm.expectRevert(LeveragedBasisTSA.LBT_InvalidGainPerUnit.selector);
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp, tradeData, tradeHelperVars);

    // accepted if the maxBaseLossPerPerp is exactly met
    _setMaxLossBounds(0.01e18, 0.005e18);
    lbtsa.verifyTradeMarkLossEma(0, block.timestamp, tradeData, tradeHelperVars);
  }

  // Edge Cases
  // ----------
  function test_ema_edge_cases_zero_values() public {
    // TODO
  }

  /////////////
  // Helpers //
  /////////////
  function _setEMAParams(uint emaDecayFactor, uint markLossEmaTarget) internal {
    LeveragedBasisTSA.LBTSAParams memory lbParams = lbtsa.getLBTSAParams();
    lbParams.emaDecayFactor = emaDecayFactor;
    lbParams.markLossEmaTarget = markLossEmaTarget;
    lbtsa.setLBTSAParams(lbParams);
  }

  function _setMaxLossBounds(int maxBaseLossPerBase, int maxBaseLossPerPerp) internal {
    LeveragedBasisTSA.LBTSAParams memory lbParams = lbtsa.getLBTSAParams();
    lbParams.maxBaseLossPerBase = maxBaseLossPerBase;
    lbParams.maxBaseLossPerPerp = maxBaseLossPerPerp;
    lbtsa.setLBTSAParams(lbParams);
  }

  function _getTradeData(int amount, int limitPrice, uint worstFee, bool isBid)
    internal
    view
    returns (ITradeModule.TradeData memory tradeData)
  {
    tradeData.desiredAmount = amount;
    tradeData.limitPrice = limitPrice;
    tradeData.worstFee = worstFee;
    tradeData.isBid = isBid;
    return tradeData;
  }

  function _getDefaultTradeHelperVars()
    internal
    view
    returns (LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars)
  {
    return LeveragedBasisTSA.TradeHelperVars({
      isBaseTrade: true,
      basePrice: 2000e18,
      perpPrice: 2000e18,
      perpPosition: 0,
      baseBalance: 20e18,
      cashBalance: 0, // ignored for delta calc
      underlyingBase: 20e18
    });
  }

  function _validateEMAValues(int expectedMarkLossEma, uint expectedMarkLossLastTs) internal {
    (int markLossEma, uint markLossLastTs) = lbtsa.getLBTSAEmaValues();
    assertEq(markLossEma, expectedMarkLossEma);
    assertEq(markLossLastTs, expectedMarkLossLastTs);
  }

  function _validateEMAValuesClose(int expectedMarkLossEma, uint expectedMarkLossLastTs, uint emaTolerance) internal {
    (int markLossEma, uint markLossLastTs) = lbtsa.getLBTSAEmaValues();
    assertApproxEqAbs(markLossEma, expectedMarkLossEma, emaTolerance);
    assertEq(markLossLastTs, expectedMarkLossLastTs);
  }
}
