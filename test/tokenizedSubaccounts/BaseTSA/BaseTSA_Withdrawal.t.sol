pragma solidity ^0.8.18;

import "../utils/CCTSATestUtils.sol";
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

contract CCTSA_BaseTSA_WithdrawalTests is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA(MARKET);
    setupCCTSA();
  }

  function testWithdrawals() public {
    _depositToTSA(1000 * MARKET_UNIT);

    // withdrawals are processed sequentially

    cctsa.requestWithdrawal(100 * MARKET_UNIT);
    cctsa.requestWithdrawal(200 * MARKET_UNIT);
    cctsa.requestWithdrawal(300 * MARKET_UNIT);

    // totalSupply includes pending withdrawals
    assertEq(cctsa.totalPendingWithdrawals(), 600 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 1000 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 0);

    cctsa.processWithdrawalRequests(1);
    assertEq(cctsa.totalPendingWithdrawals(), 500 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 900 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 100 * MARKET_UNIT);

    cctsa.processWithdrawalRequests(1);
    assertEq(cctsa.totalPendingWithdrawals(), 300 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 700 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 300 * MARKET_UNIT);

    cctsa.processWithdrawalRequests(1);
    assertEq(cctsa.totalPendingWithdrawals(), 0);
    assertEq(cctsa.totalSupply(), 400 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 600 * MARKET_UNIT);
  }

  function testWithdrawalReverts() public {
    _depositToTSA(1000 * MARKET_UNIT);

    // withdrawals are blocked when there is a liquidation
    uint w1 = cctsa.requestWithdrawal(100 * MARKET_UNIT);
    uint w2 = cctsa.requestWithdrawal(200 * MARKET_UNIT);
    uint w3 = cctsa.requestWithdrawal(300 * MARKET_UNIT);

    uint auctionId = _createInsolventAuction();
    assertTrue(auction.getIsWithdrawBlocked());

    vm.expectRevert(BaseTSA.BTSA_Blocked.selector);
    cctsa.processWithdrawalRequests(1);

    // clear auction
    _clearAuction(auctionId);

    // only shareKeeper can process withdrawals before the withdrawal delay
    vm.prank(address(0xaa));
    vm.expectRevert(BaseTSA.BTSA_OnlyShareKeeper.selector);
    cctsa.processWithdrawalRequests(1);

    // nothing happened, check state
    assertEq(cctsa.totalPendingWithdrawals(), 600 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 1000 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 0);

    cctsa.processWithdrawalRequests(1);

    // check state
    assertEq(cctsa.totalPendingWithdrawals(), 500 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 900 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 100 * MARKET_UNIT);

    // cannot be processed if no funds available for withdraw
    _executeDeposit(900 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(tsa)), 0);

    cctsa.processWithdrawalRequests(1);

    // check state
    assertEq(cctsa.totalPendingWithdrawals(), 500 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 900 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 100 * MARKET_UNIT);

    // can be processed partially if not enough funds available

    // partially withdraw, so 50 can be filled of the withdrawal request
    _executeWithdrawal(50 * MARKET_UNIT);

    cctsa.processWithdrawalRequests(1);

    BaseTSA.WithdrawalRequest memory withdrawReq = cctsa.queuedWithdrawal(w2);
    assertEq(withdrawReq.amountShares, 150 * MARKET_UNIT);
    assertEq(withdrawReq.assetsReceived, 50 * MARKET_UNIT);

    // check state
    assertEq(cctsa.totalPendingWithdrawals(), 450 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 850 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 150 * MARKET_UNIT);

    // withdrawals cannot be processed if already processed
    _executeWithdrawal(350 * MARKET_UNIT);

    cctsa.processWithdrawalRequests(2);

    // check state
    // 100 remaining for w3
    assertEq(cctsa.totalPendingWithdrawals(), 100 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 500 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 500 * MARKET_UNIT);

    withdrawReq = cctsa.queuedWithdrawal(w2);
    assertEq(withdrawReq.amountShares, 0);
    assertEq(withdrawReq.assetsReceived, 200 * MARKET_UNIT);

    withdrawReq = cctsa.queuedWithdrawal(w3);
    assertEq(withdrawReq.amountShares, 100 * MARKET_UNIT);
    assertEq(withdrawReq.assetsReceived, 200 * MARKET_UNIT);
  }

  function testWithdrawalMultiple() public {
    _depositToTSA(1000 * MARKET_UNIT);

    // can have multiple processed in one transaction, will stop once no funds available
    cctsa.requestWithdrawal(100 * MARKET_UNIT);
    vm.warp(block.timestamp + 1 days);
    cctsa.requestWithdrawal(200 * MARKET_UNIT);
    vm.warp(block.timestamp + 2 days);
    cctsa.requestWithdrawal(300 * MARKET_UNIT);

    vm.warp(block.timestamp + 5 days);

    cctsa.processWithdrawalRequests(2);

    // check state
    assertEq(cctsa.totalPendingWithdrawals(), 300 * MARKET_UNIT);
    assertEq(cctsa.totalSupply(), 700 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);
    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 300 * MARKET_UNIT);
  }

  function testWithdrawScale() public {
    _depositToTSA(1000 * MARKET_UNIT);

    BaseTSA.TSAParams memory params = cctsa.getTSAParams();
    params.withdrawScale = 0.9e18;
    cctsa.setTSAParams(params);

    uint w1 = cctsa.requestWithdrawal(100 * MARKET_UNIT);
    uint w2 = cctsa.requestWithdrawal(200 * MARKET_UNIT);
    uint w3 = cctsa.requestWithdrawal(300 * MARKET_UNIT);

    cctsa.processWithdrawalRequests(3);

    // Each withdrawal will get half of the requested amount, meaning future ones will
    // get more and more

    assertEq(cctsa.totalPendingWithdrawals(), 0);
    assertEq(cctsa.totalSupply(), 400 * MARKET_UNIT);
    assertEq(cctsa.balanceOf(address(this)), 400 * MARKET_UNIT);

    BaseTSA.WithdrawalRequest memory withdrawReq = cctsa.queuedWithdrawal(w1);
    assertEq(withdrawReq.amountShares, 0);
    assertEq(withdrawReq.assetsReceived, 90 * MARKET_UNIT);

    withdrawReq = cctsa.queuedWithdrawal(w2);
    assertEq(withdrawReq.amountShares, 0);
    // (200 * 0.9 / 900) * 910
    assertApproxEqAbs(withdrawReq.assetsReceived, 182 * MARKET_UNIT, 0.000001e18);

    withdrawReq = cctsa.queuedWithdrawal(w3);
    assertEq(withdrawReq.amountShares, 0);
    // (300 * 0.9 / 700) * 728
    assertApproxEqAbs(withdrawReq.assetsReceived, 2808 * MARKET_UNIT / 10, 0.000001e18);

    assertApproxEqAbs(markets[MARKET].erc20.balanceOf(address(this)), 5528 * MARKET_UNIT / 10, 0.000001e18);
  }

  function testWithdrawReverts() public {
    vm.expectRevert(BaseTSA.BTSA_InsufficientBalance.selector);
    cctsa.requestWithdrawal(100 * MARKET_UNIT);

    vm.expectRevert(BaseTSA.BTSA_InvalidWithdrawalAmount.selector);
    cctsa.requestWithdrawal(0);
  }
}
