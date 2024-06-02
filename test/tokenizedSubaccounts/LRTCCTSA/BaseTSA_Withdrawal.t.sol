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
}
