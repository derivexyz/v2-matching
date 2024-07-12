// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "./TSATestUtils.sol";

/// @notice proof of concept integration tests for PPTSA
contract PPTSATest is PPTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth");
    setupPPTSA();
  }

  // test this as maker too
  function testPPCanDepositTradeWithdraw() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(tsa), 10e18);
    uint depositId = tsa.initiateDeposit(1e18, address(this));
    tsa.processDeposit(depositId);

    // shares equal to spot price of 1 weth
    assertEq(tsa.balanceOf(address(this)), 1e18);

    _executeDeposit(0.8e18);

    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0.2e18);
    assertEq(subAccounts.getBalance(tsa.subAccount(), markets["weth"].base, 0), 0.8e18);

    depositId = tsa.initiateDeposit(1e18, address(this));
    tsa.processDeposit(depositId);

    assertEq(tsa.balanceOf(address(this)), 2e18);

    // Withdraw with no PnL

    tsa.requestWithdrawal(0.25e18);

    assertEq(tsa.balanceOf(address(this)), 1.75e18);
    assertEq(tsa.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    tsa.processWithdrawalRequests(1);

    assertEq(tsa.balanceOf(address(this)), 1.75e18);
    assertEq(tsa.totalPendingWithdrawals(), 0);

    assertEq(markets["weth"].erc20.balanceOf(address(this)), 8.25e18); // holding 8 previously

    _executeDeposit(0.5e18);

    uint expiry = block.timestamp + 1 weeks;
    (,, int cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, 0);
    // this means that the higher strike should be positive.
    // taker means the higher strike is negative
    _tradeRfqAsMaker(1e18, 3.9e18, expiry, 400e18, 4e18, 800e18);
    (,, cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, 1e17);

    vm.warp(block.timestamp + 7 days);
    (,, cashBalance) = tsa.getSubAccountStats();
    _executeWithdrawal(0.5e18);

    assertEq(subAccounts.getBalance(tsa.subAccount(), markets["weth"].base, 0), 0.8e18);
  }

  function testPPCanTradeAsTaker() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(tsa), 10e18);
    uint depositId = tsa.initiateDeposit(4e18, address(this));
    tsa.processDeposit(depositId);

    _executeDeposit(4e18);
    (,, int cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, 0);
    _tradeRfqAsTaker(1e18, 3.9e18, block.timestamp + 1 weeks, 800e18, 4.0e18, 400e18);
    (,, cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, -1e17);
  }
}
