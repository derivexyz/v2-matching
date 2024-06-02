pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Account Value
- correctly calculates the account value when there is no ongoing liquidation.
- correctly includes the deposit asset balance in the account value calculation.
- correctly includes the mark-to-market value in the account value calculation.
- correctly converts the mark-to-market value to the base asset's value.
- reverts when the position is insolvent due to a negative mark-to-market value exceeding the deposit asset balance.
- returns zero when there are no assets or liabilities in the account.
- correctly handles the scenario when the mark-to-market value is positive.
- correctly handles the scenario when the mark-to-market value is negative but does not exceed the deposit asset balance.

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
}
