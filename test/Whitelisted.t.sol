// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "v2-core/test/integration-tests/shared/IntegrationTestBase.sol";
import {Matching} from "src/Matching.sol";

/**
 * @dev Unit tests for the whitelisted functions
 */
contract UNIT_MatchingWhitelistedFunctions is IntegrationTestBase {
  using SafeCast for int;

  Matching matching;
  bytes32 public domainSeparator;

  constructor() {}

  function setUp() public {
    _setupIntegrationTestComplete();

    matching = new Matching(accounts, cash, 420);
    domainSeparator = matching.domainSeparator();
    matching.setWhitelist(address(this), true);

    vm.startPrank(alice);
    accounts.approve(address(matching), aliceAcc);
    matching.openCLOBAccount(aliceAcc);
    vm.stopPrank();

    vm.startPrank(bob);
    accounts.approve(address(matching), bobAcc);
    matching.openCLOBAccount(bobAcc);
    vm.stopPrank();

    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
  }

  function testCanTransferAsset() public {
    uint transferAmount = 10e18;
    int alicePrevious = getCashBalance(aliceAcc);
    int bobPrevious = getCashBalance(bobAcc);
    assertEq(alicePrevious.toUint256(), DEFAULT_DEPOSIT);
    assertEq(bobPrevious.toUint256(), DEFAULT_DEPOSIT);

    matching.transferAsset(aliceAcc, bobAcc, cash, 0, transferAmount);
    int aliceAfter = getCashBalance(aliceAcc);
    int bobAfter = getCashBalance(bobAcc);
    assertEq(aliceAfter.toUint256(), DEFAULT_DEPOSIT - transferAmount);
    assertEq(bobAfter.toUint256(), DEFAULT_DEPOSIT + transferAmount);
  }

  function testCannotTransferAsset() public {
    // Remove whitelist and try to transfer
    matching.setWhitelist(address(this), false);

    vm.expectRevert(Matching.M_NotWhitelisted.selector);
    matching.transferAsset(aliceAcc, bobAcc, cash, 0, 1e18);
  }
}
