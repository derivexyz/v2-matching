pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Tests for TSA signing
- only signers can sign
- only signers can revoke
- only signers can revoke action signatures
- signatures are stored correctly
- signatures can be revoked
- signatures can be revoked for actions
- signatures can be verified
*/

contract LRTCCTSA_BaseOnChainSigningTSATests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }
}
