// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {SubAccountsManager, ISubAccountsManager} from "src/SubAccountsManager.sol";

contract SubAccountManagementTest is MatchingBase {
  function testCanCreateAccount() public {
    vm.startPrank(cam);
    uint newAcc = matching.createSubAccount(IManager(pmrm));
    vm.stopPrank();

    assertEq(subAccounts.ownerOf(newAcc), address(matching));
    assertEq(matching.subAccountToOwner(newAcc), cam);
  }

  function testCanDepositAccount() public {
    uint newAcc = subAccounts.createAccount(cam, pmrm);

    vm.startPrank(cam);
    subAccounts.approve(address(matching), newAcc);
    matching.depositSubAccount(newAcc);
    vm.stopPrank();

    assertEq(subAccounts.ownerOf(newAcc), address(matching));
    assertEq(matching.subAccountToOwner(newAcc), cam);
  }

  function testCanWithdrawAccount() public {
    // camAcc is already deposited
    vm.startPrank(cam);
    matching.requestWithdrawAccount(camAcc);
    vm.warp(block.timestamp + (1 hours));
    matching.completeWithdrawAccount(camAcc);
    vm.stopPrank();

    assertEq(subAccounts.ownerOf(camAcc), cam);
    assertEq(matching.subAccountToOwner(camAcc), address(0));
  }

  function testCannotRequestWithdrawFromNonOwner() public {
    vm.expectRevert(ISubAccountsManager.SAM_NotOwnerAddress.selector);

    vm.prank(doug);
    matching.requestWithdrawAccount(camAcc);
  }

  function testCannotWithdrawDuringCooldown() public {
    vm.startPrank(cam);
    matching.requestWithdrawAccount(camAcc);

    vm.expectRevert(ISubAccountsManager.SAM_CooldownNotElapsed.selector);

    matching.completeWithdrawAccount(camAcc);
    vm.stopPrank();
  }

  function testCanCompleteWithNotOwner() public {
    vm.startPrank(cam);
    matching.requestWithdrawAccount(camAcc);
    vm.warp(block.timestamp + (1 hours));
    vm.stopPrank();

    vm.prank(doug);
    matching.completeWithdrawAccount(camAcc);
  }
}
