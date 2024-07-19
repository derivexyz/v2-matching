// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../TSATestUtils.sol";

import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

contract PPTSA_ValidationTests is PPTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth", true, true);
    setupPPTSA();
  }

  function testPPTWithdrawalBaseAssetValidation() public {
    _depositToTSA(3e18);
    vm.startPrank(signer);

    // correctly verifies withdrawal actions.
    IActionVerifier.Action memory action = _createWithdrawalAction(3e18);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidBaseBalance.selector);
    tsa.signActionData(action, "");

    // reverts for invalid assets.
    action.data = _encodeWithdrawData(3e18, address(11111));
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidAsset.selector);
    tsa.signActionData(action, "");

    vm.stopPrank();

    // add a trade
    uint expiry = block.timestamp + 1 weeks;
    _executeDeposit(3e18);
    _tradeRfqAsTaker(1e18, 1e18, expiry, 2000e18, 4.0e18, 1600e18, true);

    action = _createWithdrawalAction(3e18);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WithdrawingWithOpenTrades.selector);
    tsa.signActionData(action, "");

    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", uint64(expiry), 1500e18);
    srm.settleOptions(markets["weth"].option, tsa.subAccount());

    vm.startPrank(signer);
    // now try to withdraw all of the base asset. Should fail
    action = _createWithdrawalAction(3e18);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WithdrawingUtilisedCollateral.selector);
    tsa.signActionData(action, "");

    // now try to a small 5% of the base asset. Should pass
    action = _createWithdrawalAction(0.15e18);
    tsa.signActionData(action, "");

    vm.stopPrank();
  }
}
