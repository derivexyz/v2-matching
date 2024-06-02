pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Fees:
- no fee is collected if the feeRecipient is the zero address
- no fee is collected if the fee is 0
- fees are collected correctly
- fees are collected correctly when decimals are different
*/

contract LRTCCTSA_BaseTSA_FeesTests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }
}
