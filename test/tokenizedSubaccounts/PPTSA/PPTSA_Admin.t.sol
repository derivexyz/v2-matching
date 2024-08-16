// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../TSATestUtils.sol";

import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

contract PPTSA_Admin is PPTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth", true, true);
    setupPPTSA();
  }

  function testPPTAdmin() public {
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    CollateralManagementTSA.CollateralManagementParams memory collateralManagementParams =
      defaultCollateralManagementParams;
    collateralManagementParams.feeFactor = 0.05e18;
    params.minSignatureExpiry = 6 minutes;

    // Only the owner can set the PPTSAParams.
    vm.prank(address(10));
    vm.expectRevert();
    tsa.setPPTSAParams(params);
    tsa.setCollateralManagementParams(collateralManagementParams);

    // The PPTSAParams are correctly set and retrieved.
    tsa.setPPTSAParams(params);
    assertEq(tsa.getPPTSAParams().minSignatureExpiry, 6 minutes);

    // Test collateralManagementParams are set and retrieved.
    tsa.setCollateralManagementParams(collateralManagementParams);
    assertEq(tsa.getCollateralManagementParams().feeFactor, 0.05e18);
  }

  function testPPTParamLimits() public {
    // test each boundary one by one
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    CollateralManagementTSA.CollateralManagementParams memory collateralManagementParams =
      defaultCollateralManagementParams;

    params.minSignatureExpiry = 1 minutes - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.minSignatureExpiry = defaultPPTSAParams.minSignatureExpiry;
    params.maxSignatureExpiry = defaultPPTSAParams.minSignatureExpiry - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxSignatureExpiry = defaultPPTSAParams.maxSignatureExpiry;
    collateralManagementParams.worstSpotBuyPrice = 1e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setCollateralManagementParams(collateralManagementParams);

    collateralManagementParams.worstSpotBuyPrice = 1.2e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setCollateralManagementParams(collateralManagementParams);

    collateralManagementParams.worstSpotBuyPrice = defaultCollateralManagementParams.worstSpotBuyPrice;
    collateralManagementParams.worstSpotSellPrice = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setCollateralManagementParams(collateralManagementParams);

    collateralManagementParams.worstSpotSellPrice = 0.8e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setCollateralManagementParams(collateralManagementParams);

    collateralManagementParams.worstSpotSellPrice = defaultCollateralManagementParams.worstSpotSellPrice;
    collateralManagementParams.spotTransactionLeniency = 1e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setCollateralManagementParams(collateralManagementParams);

    collateralManagementParams.spotTransactionLeniency = 1.2e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setCollateralManagementParams(collateralManagementParams);

    collateralManagementParams.spotTransactionLeniency = defaultCollateralManagementParams.spotTransactionLeniency;
    params.maxTotalCostTolerance = 1e17;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxTotalCostTolerance = defaultPPTSAParams.maxTotalCostTolerance;
    params.maxTotalCostTolerance = 6e18;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxTotalCostTolerance = defaultPPTSAParams.maxTotalCostTolerance;
    params.maxLossOrGainPercentOfTVL = 0;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxLossOrGainPercentOfTVL = defaultPPTSAParams.maxLossOrGainPercentOfTVL;
    params.maxLossOrGainPercentOfTVL = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxLossOrGainPercentOfTVL = defaultPPTSAParams.maxLossOrGainPercentOfTVL;
    params.negMaxCashTolerance = 1e16 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxLossOrGainPercentOfTVL = defaultPPTSAParams.maxLossOrGainPercentOfTVL;
    params.strikeDiff = 0;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.strikeDiff = defaultPPTSAParams.strikeDiff;
    params.negMaxCashTolerance = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.negMaxCashTolerance = defaultPPTSAParams.negMaxCashTolerance;
    params.optionMaxTimeToExpiry = defaultPPTSAParams.optionMinTimeToExpiry - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.optionMaxTimeToExpiry = defaultPPTSAParams.optionMaxTimeToExpiry;
    params.minMarkValueToStrikeDiffRatio = 0;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.minMarkValueToStrikeDiffRatio = defaultPPTSAParams.minMarkValueToStrikeDiffRatio;
    tsa.setPPTSAParams(params);
    tsa.setCollateralManagementParams(collateralManagementParams);
  }
}
