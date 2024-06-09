pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Withdrawals:
- ✅withdrawals are processed sequentially
- ✅withdrawals are blocked when there is a liquidation
- ✅only shareKeeper can process withdrawals before the withdrawal delay
- ✅withdrawals can be processed by anyone if not processed in time
- ✅cannot be processed if no funds available for withdraw
- ✅can be processed partially if not enough funds available
- ✅withdrawals cannot be processed if already processed
- ✅can have multiple processed in one transaction, will stop once no funds available
- ✅can have multiple processed in one transaction, will stop once withdrawal delay is not met
- ✅withdrawals will be scaled by the withdrawScale
- withdrawals will collect fees correctly (before totalSupply is changed)
*/

contract LRTCCTSA_BaseTSA_WithdrawalTests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }

  function testWithdrawals() public {
    _depositToTSA(1000e18);

    // withdrawals are processed sequentially

    tsa.requestWithdrawal(100e18);
    tsa.requestWithdrawal(200e18);
    tsa.requestWithdrawal(300e18);

    // totalSupply includes pending withdrawals
    assertEq(tsa.totalPendingWithdrawals(), 600e18);
    assertEq(tsa.totalSupply(), 1000e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 0);

    tsa.processWithdrawalRequests(1);
    assertEq(tsa.totalPendingWithdrawals(), 500e18);
    assertEq(tsa.totalSupply(), 900e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 100e18);

    tsa.processWithdrawalRequests(1);
    assertEq(tsa.totalPendingWithdrawals(), 300e18);
    assertEq(tsa.totalSupply(), 700e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 300e18);

    tsa.processWithdrawalRequests(1);
    assertEq(tsa.totalPendingWithdrawals(), 0);
    assertEq(tsa.totalSupply(), 400e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 600e18);
  }

  function testWithdrawalReverts() public {
    _depositToTSA(1000e18);

    // withdrawals are blocked when there is a liquidation
    uint w1 = tsa.requestWithdrawal(100e18);
    uint w2 = tsa.requestWithdrawal(200e18);
    uint w3 = tsa.requestWithdrawal(300e18);

    uint auctionId = _createInsolventAuction();
    assertTrue(auction.getIsWithdrawBlocked());

    vm.expectRevert(BaseTSA.BTSA_Blocked.selector);
    tsa.processWithdrawalRequests(1);

    // clear auction
    _clearAuction(auctionId);

    // only shareKeeper can process withdrawals before the withdrawal delay
    vm.prank(address(0xaa));
    tsa.processWithdrawalRequests(1);

    // nothing happened, check state
    assertEq(tsa.totalPendingWithdrawals(), 600e18);
    assertEq(tsa.totalSupply(), 1000e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 0);

    // withdrawals can be processed by anyone if not processed in time
    vm.warp(block.timestamp + 1 weeks);
    vm.prank(address(0xaa));
    tsa.processWithdrawalRequests(1);

    // check state
    assertEq(tsa.totalPendingWithdrawals(), 500e18);
    assertEq(tsa.totalSupply(), 900e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 100e18);

    // cannot be processed if no funds available for withdraw
    _executeDeposit(900e18);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0);

    tsa.processWithdrawalRequests(1);

    // check state
    assertEq(tsa.totalPendingWithdrawals(), 500e18);
    assertEq(tsa.totalSupply(), 900e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 100e18);

    // can be processed partially if not enough funds available

    // partially withdraw, so 50 can be filled of the withdrawal request
    _executeWithdrawal(50e18);

    tsa.processWithdrawalRequests(1);

    BaseTSA.WithdrawalRequest memory withdrawReq = tsa.queuedWithdrawal(w2);
    assertEq(withdrawReq.amountShares, 150e18);
    assertEq(withdrawReq.assetsReceived, 50e18);

    // check state
    assertEq(tsa.totalPendingWithdrawals(), 450e18);
    assertEq(tsa.totalSupply(), 850e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 150e18);

    // withdrawals cannot be processed if already processed
    _executeWithdrawal(350e18);

    tsa.processWithdrawalRequests(2);

    // check state
    // 100 remaining for w3
    assertEq(tsa.totalPendingWithdrawals(), 100e18);
    assertEq(tsa.totalSupply(), 500e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 500e18);

    withdrawReq = tsa.queuedWithdrawal(w2);
    assertEq(withdrawReq.amountShares, 0);
    assertEq(withdrawReq.assetsReceived, 200e18);

    withdrawReq = tsa.queuedWithdrawal(w3);
    assertEq(withdrawReq.amountShares, 100e18);
    assertEq(withdrawReq.assetsReceived, 200e18);
  }

  function testWithdrawalMultiple() public {
    _depositToTSA(1000e18);

    // can have multiple processed in one transaction, will stop once no funds available
    tsa.requestWithdrawal(100e18);
    vm.warp(block.timestamp + 1 days);
    tsa.requestWithdrawal(200e18);
    vm.warp(block.timestamp + 2 days);
    tsa.requestWithdrawal(300e18);

    // anyone should be able to process 1 and 2
    vm.warp(block.timestamp + 5 days);

    vm.prank(address(0xaa));
    tsa.processWithdrawalRequests(3);

    // check state
    assertEq(tsa.totalPendingWithdrawals(), 300e18);
    assertEq(tsa.totalSupply(), 700e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);
    assertEq(markets["weth"].erc20.balanceOf(address(this)), 300e18);
  }

  function testWithdrawScale() public {
    _depositToTSA(1000e18);

    BaseTSA.TSAParams memory params = tsa.getTSAParams();
    params.withdrawScale = 0.9e18;
    tsa.setTSAParams(params);

    uint w1 = tsa.requestWithdrawal(100e18);
    uint w2 = tsa.requestWithdrawal(200e18);
    uint w3 = tsa.requestWithdrawal(300e18);

    tsa.processWithdrawalRequests(3);

    // Each withdrawal will get half of the requested amount, meaning future ones will
    // get more and more

    assertEq(tsa.totalPendingWithdrawals(), 0);
    assertEq(tsa.totalSupply(), 400e18);
    assertEq(tsa.balanceOf(address(this)), 400e18);

    BaseTSA.WithdrawalRequest memory withdrawReq = tsa.queuedWithdrawal(w1);
    assertEq(withdrawReq.amountShares, 0);
    assertEq(withdrawReq.assetsReceived, 90e18);

    withdrawReq = tsa.queuedWithdrawal(w2);
    assertEq(withdrawReq.amountShares, 0);
    // (200 * 0.9 / 900) * 910
    assertApproxEqAbs(withdrawReq.assetsReceived, 182e18, 0.000001e18);

    withdrawReq = tsa.queuedWithdrawal(w3);
    assertEq(withdrawReq.amountShares, 0);
    // (300 * 0.9 / 700) * 728
    assertApproxEqAbs(withdrawReq.assetsReceived, 280.8e18, 0.000001e18);

    assertApproxEqAbs(markets["weth"].erc20.balanceOf(address(this)), 552.8e18, 0.000001e18);
  }
}
