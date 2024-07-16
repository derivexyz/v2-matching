// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "./TSATestUtils.sol";

/// @notice proof of concept integration tests for PPTSA
contract PPTSATest is PPTSATestUtils {
  using SignedMath for int;

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

    uint64 expiry = uint64(block.timestamp + 1 weeks);
    (,, int cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, 0);
    _tradeRfqAsMaker(1e18, 3.9e18, expiry, 400e18, 4e18, 800e18, true);
    (,, cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, 1e17);

    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", expiry, 2500e18);
    srm.settleOptions(markets["weth"].option, tsa.subAccount());
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
    _tradeRfqAsTaker(1e18, 3.9e18, block.timestamp + 1 weeks, 800e18, 4.0e18, 400e18, true);
    (,, cashBalance) = tsa.getSubAccountStats();
    assertEq(cashBalance, -1e17);
  }

  function testMakerTakerSpreadCombinations() public {
    _depositToTSA(100e18);
    _executeDeposit(100e18);
    int amount = 1e18;
    uint higherPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    // rename to low price
    uint lowerPrice = 250e18;
    uint lowStrike = 1600e18;

    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    console2.log("Second test");
    (uint openSpreads, uint baseBalance, int cashBalance) = tsa.getSubAccountStats();

    params.isLongSpread = false;
    params.maxTotalCostTolerance = 5e17;
    tsa.setPPTSAParams(params);
    // we are the taker buying a short call spread
    _tradeRfqAsTaker(-1 * amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 200e18);

    // we are the maker buying a short call spread
    _tradeRfqAsMaker(amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, 2 * amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 400e18);

    params.isLongSpread = true;
    params.maxTotalCostTolerance = 2e18;
    tsa.setPPTSAParams(params);
    // we are a maker buying a long call spread
    _tradeRfqAsMaker(-1 * amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 200e18);

    // we are the taker buying a long call spread
    _tradeRfqAsTaker(amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, 0);
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 0);

    params.isCallSpread = false;
    params.isLongSpread = false;
    params.maxTotalCostTolerance = 5e17;
    tsa.setPPTSAParams(params);
    // we are the taker buying a short put spread
    _tradeRfqAsTaker(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, false);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 200e18);

    // we are the maker buying a short put spread
    _tradeRfqAsMaker(-1 * amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, false);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, 2 * amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 400e18);

    params.isLongSpread = true;
    params.maxTotalCostTolerance = 2e18;
    tsa.setPPTSAParams(params);
    // we are a maker buying a long put spread
    _tradeRfqAsMaker(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, false);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 200e18);

    // we are the taker buying a long put spread
    _tradeRfqAsTaker(-1 * amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, false);
    (openSpreads, baseBalance, cashBalance) = tsa.getSubAccountStats();
    assertEq(openSpreads, 0);
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, 0);
  }
}
