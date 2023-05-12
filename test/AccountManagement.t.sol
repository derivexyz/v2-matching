// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "v2-core/test/integration-tests/shared/IntegrationTestBase.sol";
import {Matching} from "src/Matching.sol";

/**
 * @dev Unit tests for the whitelisted functions
 */
contract UNIT_MatchingAccountManagement is IntegrationTestBase {
  using SafeCast for int;

  Matching matching;
  bytes32 public domainSeparator;
  uint public COOLDOWN_SEC = 1 hours;

  constructor() {}

  function setUp() public {
    _setupIntegrationTestComplete();

    matching = new Matching(accounts, cash, 420, COOLDOWN_SEC);
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

  function testCanWithdrawAccount() public {
    vm.startPrank(alice);
    matching.requestWithdraw(aliceAcc);
    assertEq(accounts.ownerOf(aliceAcc), address(matching));

    // Should revert since cooldown has no elapsed
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CooldownNotElapsed.selector, COOLDOWN_SEC));
    matching.closeCLOBAccount(aliceAcc);

    vm.warp(block.timestamp + COOLDOWN_SEC);
    matching.closeCLOBAccount(aliceAcc);
    assertEq(accounts.ownerOf(aliceAcc), address(alice));
  }

  function testCannotRequestWithdraw() public {
    vm.startPrank(bob);

    // Should revert since bob is not owner
    vm.expectRevert(abi.encodeWithSelector(Matching.M_NotOwnerAddress.selector, address(bob), address(alice)));
    matching.requestWithdraw(aliceAcc);
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
