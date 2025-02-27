pragma solidity ^0.8.18;

import "../utils/LBTSATestUtils.sol";

contract LevBasisTSA_VerifyDeltaTests is LBTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLBTSA();
    setupLBTSA();

    _setDeltaParams(1e18, 0.05e18);
  }

  // Base Trade Tests
  // ---------------
  // Test that buying spot (bid) increases delta
  // - Set initial delta near target
  // - Verify small spot buy succeeds
  // - Verify large spot buy fails when exceeding tolerance

  // Test that selling spot (ask) decreases delta
  // - Set initial delta near target
  // - Verify small spot sell succeeds
  // - Verify large spot sell fails when exceeding tolerance

  function test_lbtsa_verifyDelta_BaseIncreaseDelta() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, true);

    // Verify large spot buy fails
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify small spot buy succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify large spot buy passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  function test_lbtsa_verifyDelta_BaseDecreaseDelta() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, false);

    // Verify large spot sell fails
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify small spot sell succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify large spot sell passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  // Perp Trade Tests
  // ---------------
  // Test that buying perp (bid) decreases delta
  // - Set initial delta near target
  // - Verify small perp buy succeeds
  // - Verify large perp buy fails when exceeding tolerance

  // Test that selling perp (ask) increases delta
  // - Set initial delta near target
  // - Verify small perp sell succeeds
  // - Verify large perp sell fails when exceeding tolerance

  function test_lbtsa_verifyDelta_PerpIncreaseDelta() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, true);
    tradeHelperVars.isBaseTrade = false;

    // Verify large perp buy fails
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify small perp buy succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify large perp buy passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  function test_lbtsa_verifyDelta_PerpDecreaseDelta() public {
    // target delta is 1e18, tolerance is 0.01e18
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, false);
    tradeHelperVars.isBaseTrade = false;

    // Verify large perp sell fails
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify small perp sell succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Verify large perp sell passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  // Price Ratio Tests
  // ----------------
  // Test delta calculations with different perp/base price ratios
  // - Test with perpPrice > basePrice (ratio > 1)
  // - Test with perpPrice = basePrice (ratio = 1)
  // - Test with perpPrice < basePrice (ratio < 1)
  // - Verify delta changes scale correctly with ratio

  function test_lbtsa_verifyDelta_PriceRatioAffectsDeltaChange() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(1e18, true);
    tradeHelperVars.isBaseTrade = false;

    // trading 1 perps would be allowed, if perps are worth 10x less than base
    tradeHelperVars.perpPrice = 200e18;
    tradeHelperVars.basePrice = 2000e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // with equal prices, this would revert
    tradeHelperVars.perpPrice = 2000e18;
    tradeHelperVars.basePrice = 2000e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // the opposite holds true too, where a small perp trade is blocked if perps are worth 10x more than base
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.perpPrice = 2000e18;
    tradeHelperVars.basePrice = 100e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  // Delta Improvement Tests
  // ----------------------
  // Test trades that improve delta position
  // - Start with delta outside target range
  // - Verify trades moving delta closer to target succeed
  // - Verify trades moving delta further from target fail
  // - Test with both base and perp trades

  function test_lbtsa_verifyDelta_DeltaImprovement() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, true);

    // start with a delta of 0 (10 base, -10 perp)
    tradeHelperVars.perpPosition = -10e18;

    // verify a small perp buy succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // verify a large perp buy that would move delta further from target fails
    tradeData.desiredAmount = 20.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // verify a large perp buy that would move delta closer to target succeeds
    tradeData.desiredAmount = 19.9e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // verify a large perp buy that would make delta the same would fail
    tradeData.desiredAmount = 20e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  // Edge Cases
  // ---------
  // Test zero value scenarios
  // - Test with zero underlyingBase (should revert)
  // - Test with zero baseBalance

  function test_lbtsa_verifyDelta_EdgeCases_ZeroValues() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, true);

    // UnderlyingBase = 0
    tradeHelperVars.underlyingBase = 0;
    vm.expectRevert();
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // BaseBalance = 0
    tradeHelperVars.underlyingBase = 10e18;
    tradeHelperVars.baseBalance = 0;
    // delta would be massively negative, should be able to open either perp or base
    tradeData.desiredAmount = 10e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.isBaseTrade = false;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.isBaseTrade = true;
    tradeHelperVars.baseBalance = 10e18;
  }

  // Test extreme value scenarios
  // - Test with very large baseBalance values
  // - Test with very large trade amounts
  // - Test with very large price ratios
  // - Verify no overflow/underflow occurs

  function test_lbtsa_verifyDelta_ExtremeValueScenarios_LargeValues() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, true);

    // Test with very large baseBalance values
    tradeHelperVars.baseBalance = 10_000_000e18;
    tradeData.desiredAmount = 0.1e18; // A large trade amount
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector); // Expect revert due to already being past the delta threshold
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Test with very large trade amounts
    tradeHelperVars.baseBalance = 10e18; // Reset base balance
    tradeData.desiredAmount = 100_000_000_000e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector); // Expect revert due to delta limits
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // Test with very large price ratios
    tradeHelperVars.basePrice = 100_000_000_000e18; // Set to maximum uint value
    tradeHelperVars.perpPrice = 1e18; // Set perp price to a small value

    tradeData.desiredAmount = 100e18; // A large base trade amount will revert
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector); // Expect revert due to delta limits
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars); // Should not revert

    // but a perp trade of that size is accepted, as delta added is minimal
    tradeHelperVars.isBaseTrade = false;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.isBaseTrade = true;

    // Test with very small price ratios
    tradeHelperVars.basePrice = 1; // Set base price to a small value
    tradeHelperVars.perpPrice = 100_000_000_000e18; // Set to large uint value
    tradeData.desiredAmount = 0.1e18; // A small trade amount will be accepted
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // but even a small perp would revert
    tradeHelperVars.isBaseTrade = false;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  // Parameter Validation
  // ------------------
  // Test different delta target and tolerance settings
  // - Test with zero tolerance
  // - Test with very small tolerance
  // - Test with different target values (-1, 0, 2)

  function test_lbtsa_verifyDelta_ParameterValidation_ZeroTolerance() public {
    _setDeltaParams(1e18, 0);
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0, true);

    // a trade of size zero is accepted
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // but any direction trade of any size would revert
    tradeHelperVars.isBaseTrade = true;
    tradeData.desiredAmount = 0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.isBaseTrade = false;
    tradeData.desiredAmount = 0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.isBaseTrade = true;
    tradeData.desiredAmount = -0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    tradeHelperVars.isBaseTrade = false;
    tradeData.desiredAmount = -0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // but if delta is improving, it will be accepted
    tradeHelperVars.perpPosition = -10e18;
    tradeData.desiredAmount = 10e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  function test_lbtsa_verifyDelta_ParameterValidation_VerySmallTolerance() public {
    _setDeltaParams(1e18, 0.00000000001e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.1e18, true);

    // a regular trade would be rejected
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // but a tiny trade would be accepted
    tradeData.desiredAmount = 0.000000000001e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  function test_lbtsa_verifyDelta_ParameterValidation_NegativeTarget() public {
    _setDeltaParams(-1e18, 0.01e18);
    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.1e18, true);

    // a regular trade would be rejected because target is negative, and delta isnt improving
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // a negative perp trade would be accepted, as delta is improving
    tradeHelperVars.isBaseTrade = false;
    tradeData.desiredAmount = -1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // -20 would get us to the target delta, so it would be accepted
    tradeData.desiredAmount = -20e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // -40 would be rejected because delta is worsening, but 39 would be accepted
    // targetDelta = -1, current delta = 1, baseBalance = 10, need -20 to get to target, -3 delta would be equivalent to 1 delta
    tradeData.desiredAmount = -39e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);

    // -40 would be rejected because delta is worsening
    tradeData.desiredAmount = -40e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars);
  }

  // TODO: Combined Scenarios
  // ----------------
  // Test complex scenarios combining multiple factors
  // - Test base + perp positions
  // - Test different price ratios with different position sizes
  // - Test improvement scenarios with different price ratios

  /////////////
  // Helpers //
  /////////////
  function _setDeltaParams(int deltaTarget, int deltaTargetTolerance) internal {
    LeveragedBasisTSA.LBTSAParams memory lbParams = lbtsa.getLBTSAParams();
    lbParams.deltaTarget = deltaTarget;
    lbParams.deltaTargetTolerance = deltaTargetTolerance;
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
