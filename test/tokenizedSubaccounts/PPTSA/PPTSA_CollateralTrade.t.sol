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

  function testTradeValidation() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    // Receive positive cash from selling options
    uint64 expiry = uint64(block.timestamp + 7 days);
    _tradeRfqAsMaker(1e18, 1e18, expiry, 400e18, 4e18, 800e18, true);

    (uint openSpreads, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(openSpreads, 1e18);
    assertEq(base, 10e18);
    assertEq(cash, 3e18);

    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address(markets["weth"].base),
      subId: OptionEncoding.toSubId(expiry, 2200e18, true),
      limitPrice: int(1e18),
      desiredAmount: 2e18,
      worstFee: 1e18,
      recipientId: tsaSubacc,
      isBid: true
    });

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: tradeModule,
      data: abi.encode(tradeData),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.startPrank(signer);

    tradeData.desiredAmount = 0;
    action.data = abi.encode(tradeData);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidDesiredAmount.selector);
    tsa.signActionData(action, "");

    tradeData.desiredAmount = 2.0e18;
    action.module = IMatchingModule(address(10));
    action.data = abi.encode(tradeData);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidModule.selector);
    tsa.signActionData(action, "");

    action.module = tradeModule;
    tradeData.asset = address(markets["weth"].option);
    action.data = abi.encode(tradeData);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidAsset.selector);
    tsa.signActionData(action, "");

    tradeData.asset = address(markets["weth"].base);
    action.data = abi.encode(tradeData);
    tsa.signActionData(action, "");

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidActionExpiry.selector);
    tsa.signActionData(action, "");
  }
}
