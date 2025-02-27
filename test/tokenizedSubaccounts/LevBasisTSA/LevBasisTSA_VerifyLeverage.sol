pragma solidity ^0.8.18;

import "../utils/LBTSATestUtils.sol";

contract LevBasisTSA_VerifyLeverageTests is LBTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLBTSA();
    setupLBTSA();

    _setLeverageParams(1e18, 3e18);
  }

  // Base Trade Leverage Tests
  // -------------------------
  // Test that increasing base balance increases leverage
  // - Set initial leverage near floor
  // - Verify small base buy succeeds
  // - Verify large base buy fails when exceeding ceiling

  function test_lbtsa_verifyLeverage_BaseIncreaseLeverage() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(1e18, true);

    // starting at 1x leverage
    tradeHelperVars.baseBalance = 1e18;
    tradeHelperVars.underlyingBase = 1e18;

    _setLeverageParams(1e18, 3e18);

    // newLev = 2, within bounds
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // newLev = 3, barely within bounds
    tradeData.desiredAmount = 2e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // newLev = 3.1, above bounds
    tradeData.desiredAmount = 2.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);
  }

  // Test that decreasing base balance decreases leverage
  // - Set initial leverage near ceiling
  // - Verify small base sell succeeds
  // - Verify large base sell fails when exceeding floor

  function test_lbtsa_verifyLeverage_BaseDecreaseLeverage() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(1e18, false);

    // starting at 3x leverage
    tradeHelperVars.baseBalance = 3e18;
    tradeHelperVars.underlyingBase = 1e18;

    // newLev = 2, within bounds
    tradeData.desiredAmount = 1e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // newLev = 1, barely within bounds
    tradeData.desiredAmount = 2e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // newLev = 0.9, below bounds
    tradeData.desiredAmount = 2.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);
  }

  // Perp Trade Leverage Tests
  // -------------------------
  // Test that perp trades do not affect leverage
  // - Verify perp buy does not change leverage
  // - Verify perp sell does not change leverage

  function test_lbtsa_verifyLeverage_PerpTradesDoNotAffectLeverage() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(1e18, true);

    tradeHelperVars.isBaseTrade = false;

    // perp trades are ignored for leverage calc
    tradeData.desiredAmount = 1_000_000e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    tradeData.isBid = false;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);
  }

  // Leverage Improvement Tests
  // --------------------------
  // Test trades that improve leverage position
  // - Start with leverage outside target range
  // - Verify trades moving leverage closer to target succeed
  // - Verify trades moving leverage further from target fail

  function test_lbtsa_verifyLeverage_LeverageImprovement() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(1e18, false); // sell

    tradeHelperVars.baseBalance = 100e18;
    tradeHelperVars.underlyingBase = 20e18;

    // starting at 5x leverage, any decrease down to 1x leverage is allowed
    tradeData.desiredAmount = 1e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    tradeData.isBid = true; // buy
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    tradeData.isBid = false; // sell
    tradeData.desiredAmount = 30e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // going from 5x to 1x is allowed
    tradeData.desiredAmount = 80e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // going below 1x is not allowed
    tradeData.desiredAmount = 80.01e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);
  }

  // Edge Cases
  // ----------
  // Test zero value scenarios
  // - Test with zero underlyingBase (should revert)
  // - Test with zero baseBalance
  // - Test with low leverage ceiling

  function test_lbtsa_verifyLeverage_EdgeCases_ZeroValues() public {
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(1e18, false); // sell

    tradeHelperVars.underlyingBase = 0;
    vm.expectRevert(); // division by zero
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // cannot reduce base balance below 0
    tradeHelperVars.underlyingBase = 1e18;
    tradeHelperVars.baseBalance = 0.5e18;
    vm.expectRevert(); // casting int to uint
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // but you can reduce leverage to 0 if params allow it
    _setLeverageParams(0, 1e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // test with low leverage ceiling
    // start at 1x leverage
    tradeHelperVars.underlyingBase = 1e18;
    tradeHelperVars.baseBalance = 1e18;
    // set ceiling to 0.5x
    _setLeverageParams(0, 0.5e18);

    // selling 0.5e18 should be allowed
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);

    // buying any amount would revert
    tradeData.isBid = true;
    tradeData.desiredAmount = 0.01e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.verifyTradeLeverage(tradeData, tradeHelperVars);
  }

  /////////////
  // Helpers //
  /////////////
  function _setLeverageParams(uint leverageFloor, uint leverageCeil) internal {
    LeveragedBasisTSA.LBTSAParams memory lbParams = lbtsa.getLBTSAParams();
    lbParams.leverageFloor = leverageFloor;
    lbParams.leverageCeil = leverageCeil;
    lbtsa.setLBTSAParams(lbParams);
  }

  function _getTradeData(int amount, bool isBid) internal view returns (ITradeModule.TradeData memory tradeData) {
    tradeData.desiredAmount = amount;
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
      baseBalance: 10e18,
      cashBalance: 0, // ignored for delta calc
      underlyingBase: 10e18
    });
  }
}
