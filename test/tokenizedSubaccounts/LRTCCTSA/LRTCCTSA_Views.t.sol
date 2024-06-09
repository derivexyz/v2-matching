pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Account Value
- correctly calculates the account value when there is no ongoing liquidation.
- correctly includes the deposit asset balance in the account value calculation.
- correctly includes the mark-to-market value in the account value calculation.
- correctly converts the mark-to-market value to the base asset's value.
- reverts when the position is insolvent due to a negative mark-to-market value exceeding the deposit asset balance.
- ✅returns zero when there are no assets or liabilities in the account.
- correctly handles the scenario when the mark-to-market value is positive.
- correctly handles the scenario when the mark-to-market value is negative but does not exceed the deposit asset balance.
- account value includes cash interest

Account Stats
- correctly retrieves the number of short calls, base balance, and cash balance.

Base Price
- correctly retrieves the base price.
*/

contract LRTCCTSA_ViewsTests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }

  function testAccountValue() public {
    assertEq(tsa.getAccountValue(false), 0);
    assertEq(tsa.getAccountValue(true), 0);

    _depositToTSA(1e18);

    assertEq(tsa.getAccountValue(false), 1e18);
    assertEq(tsa.getAccountValue(true), 1e18);

    tsa.requestWithdrawal(0.5e18);

    assertEq(tsa.getAccountValue(false), 1e18);
    assertEq(tsa.getAccountValue(true), 1e18);

    // changing spot doesnt affect withdrawal amount since there are no options/cash
    _setSpotPrice("weth", 3000e18, 1e18);

    tsa.processWithdrawalRequests(1);

    assertEq(tsa.getAccountValue(false), 0.5e18);
    assertEq(tsa.getAccountValue(true), 0.5e18);

    _depositToTSA(1.5e18);
    _executeDeposit(2e18);

    _tradeOption(-2e18, 100e18, block.timestamp + 1 weeks, 2600e18);

    (uint sc, uint base, int cash) = tsa.getSubAccountStats();

    assertEq(sc, 2e18);
    assertEq(base, 2e18);
    assertEq(cash, 200e18);

    // Options are worth very little, vault got a good price, so gained 0.08 in value
    assertApproxEqAbs(tsa.getAccountValue(false), 2.08e18, 0.01e18);

    _depositToTSA(2e18);
    _executeDeposit(2e18);

    // Can have multiple different expiries, as long as valid
    _tradeOption(-1e18, 100e18, block.timestamp + 1 weeks + 1 hours, 2600e18);
    _tradeOption(-1e18, 100e18, block.timestamp + 1 weeks + 2 hours, 2600e18);

    (sc, base, cash) = tsa.getSubAccountStats();

    assertEq(sc, 4e18);
    assertEq(base, 4e18);
    assertEq(cash, 400e18);

    assertApproxEqAbs(tsa.getAccountValue(false), 4.16e18, 0.01e18);
  }
}
