// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/Matching.sol";
import "src/modules/DepositModule.sol";
import "v2-core-test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract DepositModule is PMRMTestBase {
  SubAccounts subAccounts;

  Matching matching;
  DepositModule depositModule;

  // signer
  uint private pk;
  address private pkOwner;
  uint referenceTime;

  function setUp() public {
    super.setUp();
    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);
    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;
  }


  function testDeposit() public {

  }
}
