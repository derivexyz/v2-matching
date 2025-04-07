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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify small spot buy succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify large spot buy passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
  }

  function test_lbtsa_verifyDelta_BaseDecreaseDelta() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, false);

    // Verify large spot sell fails
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify small spot sell succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify large spot sell passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
  }

  function test_lbtsa_verifyDelta_ToZero() public {
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(10e18, false);

    // verify closing spot almost fully when no perps open is successful
    tradeData.desiredAmount = 9.9e18;

    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, true);

    // a trade would fail, as it is reducing delta too much (converting base for cash)
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // verify withdrawing everything is successful
    tradeData.desiredAmount = 10e18;

    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, true);

    // but not if there is a perp
    tradeHelperVars.perpPosition = 10e18;

    vm.expectRevert(LeveragedBasisTSA.LBT_InvalidDeltaChange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, true);
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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify small perp buy succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify large perp buy passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
  }

  function test_lbtsa_verifyDelta_PerpDecreaseDelta() public {
    // target delta is 1e18, tolerance is 0.01e18
    _setDeltaParams(1e18, 0.01e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.5e18, false);
    tradeHelperVars.isBaseTrade = false;

    // Verify large perp sell fails
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify small perp sell succeeds
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Verify large perp sell passes with different tolerance
    _setDeltaParams(1e18, 0.05e18);
    tradeData.desiredAmount = 0.5e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // with equal prices, this would revert
    tradeHelperVars.perpPrice = 2000e18;
    tradeHelperVars.basePrice = 2000e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // the opposite holds true too, where a small perp trade is blocked if perps are worth 10x more than base
    tradeData.desiredAmount = 0.1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    tradeHelperVars.perpPrice = 2000e18;
    tradeHelperVars.basePrice = 100e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // verify a large perp buy that would move delta further from target fails
    tradeData.desiredAmount = 20.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // verify a large perp buy that exceeds opposite side reverts
    tradeData.desiredAmount = 19.9e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // verify a large perp buy that would make delta the same would fail
    tradeData.desiredAmount = 20e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // verify a perp that would improve delta to target succeeds
    tradeData.desiredAmount = 10e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // BaseBalance = 0
    tradeHelperVars.underlyingBase = 10e18;
    tradeHelperVars.baseBalance = 0;
    // delta would be massively negative, should be able to open either perp or base
    tradeData.desiredAmount = 10e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    tradeHelperVars.isBaseTrade = false;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Test with very large trade amounts
    tradeHelperVars.baseBalance = 10e18; // Reset base balance
    tradeData.desiredAmount = 100_000_000_000e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector); // Expect revert due to delta limits
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Test with very large price ratios
    tradeHelperVars.basePrice = 100_000_000_000e18; // Set to maximum uint value
    tradeHelperVars.perpPrice = 1e18; // Set perp price to a small value

    tradeData.desiredAmount = 100e18; // A large base trade amount will revert
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector); // Expect revert due to delta limits
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false); // Should not revert

    // but a perp trade of that size is accepted, as delta added is minimal
    tradeHelperVars.isBaseTrade = false;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    tradeHelperVars.isBaseTrade = true;

    // Test with very small price ratios
    tradeHelperVars.basePrice = 1; // Set base price to a small value
    tradeHelperVars.perpPrice = 100_000_000_000e18; // Set to large uint value
    tradeData.desiredAmount = 0.1e18; // A small trade amount will be accepted
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // but even a small perp would revert
    tradeHelperVars.isBaseTrade = false;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
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
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // but any direction trade of any size would revert
    tradeHelperVars.isBaseTrade = true;
    tradeData.desiredAmount = 0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    tradeHelperVars.isBaseTrade = false;
    tradeData.desiredAmount = 0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    tradeHelperVars.isBaseTrade = true;
    tradeData.desiredAmount = -0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    tradeHelperVars.isBaseTrade = false;
    tradeData.desiredAmount = -0.1e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // but if delta is improving, it will be accepted
    tradeHelperVars.perpPosition = -10e18;
    tradeData.desiredAmount = 10e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
  }

  function test_lbtsa_verifyDelta_ParameterValidation_VerySmallTolerance() public {
    _setDeltaParams(1e18, 0.00000000001e18);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.1e18, true);

    // a regular trade would be rejected
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // but a tiny trade would be accepted
    tradeData.desiredAmount = 0.000000000001e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
  }

  function test_lbtsa_verifyDelta_ZeroDeltaTarget() public {
    LeveragedBasisTSA.LBTSAParams memory lbParams = lbtsa.getLBTSAParams();
    lbParams.deltaFloor = 0e18;
    lbParams.deltaCeil = 1e18;
    lbtsa.setLBTSAParams(lbParams);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.1e18, true);

    // With zero delta target, current delta is 1.0 (10 base, 0 perp)
    // Adding base would increase delta further from target
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Selling base would improve delta toward target
    tradeData.desiredAmount = 0.1e18;
    tradeData.isBid = false;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Selling perp would also improve delta toward zero
    tradeHelperVars.isBaseTrade = false;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Perfect trade to hit zero delta (sell 10 perp to balance 10 base)
    tradeData.desiredAmount = 10e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // Too large perp trade would overshoot zero delta target
    tradeData.desiredAmount = 10.5e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
  }

  function test_lbtsa_verifyDelta_ParameterValidation_NegativeTarget() public {
    LeveragedBasisTSA.LBTSAParams memory lbParams = lbtsa.getLBTSAParams();
    lbParams.deltaFloor = -3e18;
    lbParams.deltaCeil = 1e18;
    lbtsa.setLBTSAParams(lbParams);

    LeveragedBasisTSA.TradeHelperVars memory tradeHelperVars = _getDefaultTradeHelperVars();
    ITradeModule.TradeData memory tradeData = _getTradeData(0.1e18, true);

    // a regular trade would be rejected because target is negative, and delta isnt improving
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // a negative perp trade would be accepted, as delta is improving
    tradeHelperVars.isBaseTrade = false;
    tradeData.desiredAmount = -1e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // -20 would get us to the target delta, so it would be accepted
    tradeData.desiredAmount = -20e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // -40 would be accepted as it is the floor
    tradeData.desiredAmount = -40e18;
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);

    // -40.00...1 would be rejected because delta is worsening
    tradeData.desiredAmount = -40.0001e18;
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.verifyTradeDelta(tradeData, tradeHelperVars, false);
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
    lbParams.deltaFloor = deltaTarget - deltaTargetTolerance;
    lbParams.deltaCeil = deltaTarget + deltaTargetTolerance;
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
