pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Fees:
- ✅no fee is collected if the feeRecipient is the zero address
- ✅no fee is collected if the fee is 0
- ✅fees are collected correctly
- ✅fees are collected correctly with pending withdrawals
- fees are collected correctly when decimals are different
*/

contract LRTCCTSA_BaseTSA_FeesTests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }

  function testFeeCollection() public {
    // - check params are as expected for a fresh deploy
    assertEq(tsa.lastFeeCollected(), block.timestamp);

    // - check params are set correctly when a deposit comes through
    vm.warp(block.timestamp + 1 hours);

    assertEq(tsa.lastFeeCollected(), block.timestamp - 1 hours);
    _depositToTSA(1e18);
    assertEq(tsa.lastFeeCollected(), block.timestamp);

    // - check no fee is collected when feeRecipient is the zero address
    LRTCCTSA.TSAParams memory params = tsa.getTSAParams();

    params.feeRecipient = address(0);
    params.managementFee = 1e16; // 1%
    tsa.setTSAParams(params);

    vm.warp(block.timestamp + 1 hours);
    tsa.collectFee();

    assertEq(tsa.lastFeeCollected(), block.timestamp);
    assertEq(tsa.balanceOf(address(0)), 0);

    // - check no fee is collected when feeRate is 0

    params.feeRecipient = address(alice);
    params.managementFee = 0;
    tsa.setTSAParams(params);

    vm.warp(block.timestamp + 1 hours);
    tsa.collectFee();

    assertEq(tsa.lastFeeCollected(), block.timestamp);
    assertEq(tsa.balanceOf(address(alice)), 0);

    // - check fees are collected correctly

    // 1% annually
    params.managementFee = 1e16;

    tsa.setTSAParams(params);

    vm.warp(block.timestamp + 365 days);
    tsa.collectFee();

    assertEq(tsa.lastFeeCollected(), block.timestamp);
    assertEq(tsa.balanceOf(address(alice)), 0.01e18);

    // - check fees are collected correctly with pending withdrawals

    markets["weth"].spotFeed.setHeartbeat(1000 weeks);
    tsa.requestWithdrawal(0.5e18);

    vm.warp(block.timestamp + 365 days);
    tsa.collectFee();

    assertEq(tsa.lastFeeCollected(), block.timestamp);
    // alice gets more than 1% as total supply is now 1.01 instead of 1
    assertEq(tsa.balanceOf(address(alice)), 0.0201e18);

    tsa.requestWithdrawal(0.5e18);

    tsa.processWithdrawalRequests(2);

    vm.prank(alice);
    tsa.requestWithdrawal(0.0201e18);

    tsa.processWithdrawalRequests(1);

    assertEq(tsa.balanceOf(address(alice)), 0);
    assertEq(tsa.balanceOf(address(this)), 0);

    assertEq(markets["weth"].erc20.balanceOf(address(this)), uint(1e18) * 10000 / 10201);
    assertEq(markets["weth"].erc20.balanceOf(address(alice)), uint(1e18) * 201 / 10201);
  }

  function testFeeCollectionWithDifferentDecimals() public {
    // TODO
  }
}
