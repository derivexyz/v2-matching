// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "./utils/CCTSATestUtils.sol";

/// @notice Very rough integration test for CCTSA
contract CCTSATest is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets[MARKET].erc20));
    upgradeToCCTSA(MARKET);
    setupCCTSA();
  }

  function testCanDepositTradeWithdraw() public {
    markets[MARKET].erc20.mint(address(this), 10e18);
    markets[MARKET].erc20.approve(address(tsa), 10e18);
    uint depositId = cctsa.initiateDeposit(1e18, address(this));
    cctsa.processDeposit(depositId);

    // shares equal to spot price of 1 weth
    assertEq(cctsa.balanceOf(address(this)), 1e18);

    _executeDeposit(0.8e18);

    assertEq(markets[MARKET].erc20.balanceOf(address(tsa)), 0.2e18);
    assertEq(subAccounts.getBalance(cctsa.subAccount(), markets[MARKET].base, 0), 0.8e18);

    depositId = cctsa.initiateDeposit(1e18, address(this));
    cctsa.processDeposit(depositId);

    assertEq(cctsa.balanceOf(address(this)), 2e18);

    // Withdraw with no PnL

    cctsa.requestWithdrawal(0.25e18);

    assertEq(cctsa.balanceOf(address(this)), 1.75e18);
    assertEq(cctsa.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    cctsa.processWithdrawalRequests(1);

    assertEq(cctsa.balanceOf(address(this)), 1.75e18);
    assertEq(cctsa.totalPendingWithdrawals(), 0);

    assertEq(markets[MARKET].erc20.balanceOf(address(this)), 8.25e18); // holding 8 previously

    _executeDeposit(0.5e18);

    uint expiry = block.timestamp + 1 weeks;

    // Open a short perp via trade module
    _tradeOption(-1e18, 200e18, expiry, 2400e18);

    (, int mtmPre) = srm.getMarginAndMarkToMarket(cctsa.subAccount(), true, 0);
    _setForwardPrice(MARKET, uint64(expiry), 2400e18, 1e18);
    (, int mtmPost) = srm.getMarginAndMarkToMarket(cctsa.subAccount(), true, 0);

    console2.log("MTM pre: %d", mtmPre);
    console2.log("MTM post: %d", mtmPost);

    // There is now PnL

    cctsa.requestWithdrawal(0.25e18);

    assertEq(cctsa.balanceOf(address(this)), 1.5e18);
    assertEq(cctsa.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    cctsa.processWithdrawalRequests(1);

    assertEq(cctsa.balanceOf(address(this)), 1.5e18);
    assertEq(cctsa.totalPendingWithdrawals(), 0);

    assertApproxEqRel(markets[MARKET].erc20.balanceOf(address(this)), 8.5016e18, 0.001e18);
  }
}
