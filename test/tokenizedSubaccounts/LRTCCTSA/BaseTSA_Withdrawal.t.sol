pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Withdrawals:
- withdrawals are processed sequentially
- withdrawals are blocked when there is a liquidation
- only shareKeeper can process withdrawals before the withdrawal delay
- withdrawals can be processed by anyone if not processed in time
- cannot be processed if no funds available for withdraw
- can be processed partially if not enough funds available
- withdrawals cannot be processed if already processed
- can have multiple processed in one transaction, will stop once no funds available
- can have multiple processed in one transaction, will stop once withdrawal delay is not met
- withdrawals will be scaled by the withdrawScale
- withdrawals will collect fees correctly (before totalSupply is changed)
- different decimals are handled correctly
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
}
