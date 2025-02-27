pragma solidity ^0.8.18;

import "../utils/CCTSATestUtils.sol";
/*
Fees:
- ✅no fee is collected if the feeRecipient is the zero address
- ✅no fee is collected if the fee is 0
- ✅fees are collected correctly
- ✅fees are collected correctly with pending withdrawals
*/

contract CCTSA_BaseTSA_FeesTests is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA("weth");
    setupCCTSA();
  }

  function testFeeCollection() public {
    // - check params are as expected for a fresh deploy
    assertEq(cctsa.lastFeeCollected(), block.timestamp);

    // - check params are set correctly when a deposit comes through
    vm.warp(block.timestamp + 1 hours);

    assertEq(cctsa.lastFeeCollected(), block.timestamp - 1 hours);
    _depositToTSA(1e18);
    assertEq(cctsa.lastFeeCollected(), block.timestamp);

    // - check no fee is collected when feeRecipient is the zero address
    CoveredCallTSA.TSAParams memory params = cctsa.getTSAParams();

    params.feeRecipient = address(0);
    params.managementFee = 1e16; // 1%
    cctsa.setTSAParams(params);

    vm.warp(block.timestamp + 1 hours);
    cctsa.collectFee();

    assertEq(cctsa.lastFeeCollected(), block.timestamp);
    assertEq(cctsa.balanceOf(address(0)), 0);

    // - check no fee is collected when feeRate is 0

    params.feeRecipient = address(alice);
    params.managementFee = 0;
    cctsa.setTSAParams(params);

    vm.warp(block.timestamp + 1 hours);
    cctsa.collectFee();

    assertEq(cctsa.lastFeeCollected(), block.timestamp);
    assertEq(cctsa.balanceOf(address(alice)), 0);

    // - check fees are collected correctly

    // 1% annually
    params.managementFee = 1e16;

    cctsa.setTSAParams(params);

    vm.warp(block.timestamp + 365 days);
    cctsa.collectFee();

    assertEq(cctsa.lastFeeCollected(), block.timestamp);
    assertEq(cctsa.balanceOf(address(alice)), 0.01e18);

    // - check fees are collected correctly with pending withdrawals

    markets["weth"].spotFeed.setHeartbeat(1000 weeks);
    cctsa.requestWithdrawal(0.5e18);

    vm.warp(block.timestamp + 365 days);
    cctsa.collectFee();

    assertEq(cctsa.lastFeeCollected(), block.timestamp);
    // alice gets more than 1% as total supply is now 1.01 instead of 1
    assertEq(cctsa.balanceOf(address(alice)), 0.0201e18);

    cctsa.requestWithdrawal(0.5e18);

    cctsa.processWithdrawalRequests(2);

    vm.prank(alice);
    cctsa.requestWithdrawal(0.0201e18);

    cctsa.processWithdrawalRequests(1);

    assertEq(cctsa.balanceOf(address(alice)), 0);
    assertEq(cctsa.balanceOf(address(this)), 0);

    assertEq(markets["weth"].erc20.balanceOf(address(this)), uint(1e18) * 10000 / 10201);
    assertEq(markets["weth"].erc20.balanceOf(address(alice)), uint(1e18) * 201 / 10201);
  }

  function testFeeCollectionWithNoShares() public {
    CoveredCallTSA.TSAParams memory params = cctsa.getTSAParams();
    params.feeRecipient = address(alice);
    params.managementFee = 1e16; // 1%

    cctsa.setTSAParams(params);

    assertEq(cctsa.lastFeeCollected(), block.timestamp);

    // Collecing fee with 0 total supply still updates timestamp
    vm.warp(block.timestamp + 1);
    cctsa.collectFee();
    assertEq(cctsa.lastFeeCollected(), block.timestamp);
  }

  function testFeeCollectionWithDifferentDecimals() public {
    // TODO
  }
}
