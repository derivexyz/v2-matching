pragma solidity ^0.8.18;

import "../../../src/AtomicSigningExecutor.sol";
import "../utils/LBTSATestUtils.sol";

contract LevBasisTSA_ActionTests is LBTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLBTSA();
    setupLBTSA();
  }

  function testActionsRevertAsExpected() public {
    _depositToTSA(1e18);
    _executeDeposit(1e18);

    srm.setOracleContingencyParams(
      markets["weth"].id,
      IStandardManager.OracleContingencyParams({perpThreshold: 0, optionThreshold: 0, baseThreshold: 0, OCFactor: 0})
    );
    srm.setBaseAssetMarginFactor(markets["weth"].id, 0.9e18, 0.95e18);
    srm.setPerpMarginRequirements(markets["weth"].id, 0.05e18, 0.065e18);

    // Open basis position 4 times (each 0.5x more leverage)
    for (uint i = 0; i < 4; i++) {
      console.log("Opening basis position %d/%d", i, 4);
      int mtm = srm.getMargin(tsa.subAccount(), true);
      // Buy spot
      _tradeSpot(0.5e18, 2000e18);
      mtm = srm.getMargin(tsa.subAccount(), true);
      // Short perp
      _tradePerp(-0.5e18, 2000e18);
      mtm = srm.getMargin(tsa.subAccount(), true);
    }

    vm.startPrank(signer);
    IActionVerifier.Action memory action = _getSpotTradeAction(10e18, 2000e18);
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.signActionData(action, "");

    action = _getSpotTradeAction(0.5e18, 2000e18);
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.signActionData(action, "");
    vm.stopPrank();
    // Close basis position 4 times (each 0.5x more leverage)
    for (uint i = 0; i < 4; i++) {
      console.log("Closing basis position %d/%d", i, 4);
      int mtm = srm.getMargin(tsa.subAccount(), true);
      // Buy spot
      _tradeSpot(-0.5e18, 2000e18);
      mtm = srm.getMargin(tsa.subAccount(), true);
      // Short perp
      _tradePerp(0.5e18, 2000e18);
      mtm = srm.getMargin(tsa.subAccount(), true);
    }

    vm.startPrank(signer);
    action = _getSpotTradeAction(-10e18, 2000e18);
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.signActionData(action, "");

    action = _getSpotTradeAction(-0.5e18, 2000e18);
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeLeverageOutOfRange.selector);
    lbtsa.signActionData(action, "");
    vm.stopPrank();
    // TODO: test EMA is triggered

    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(lbtsa.subAccount());
    vm.assertEq(balances.length, 1);
    vm.assertEq(balances[0].balance, 1e18);

    console.log("Withdrawing everything");
    // can now withdraw everything
    _executeWithdrawal(1e18);
  }
}
