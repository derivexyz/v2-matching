
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {SubAccountsManager} from "src/SubAccountsManager.sol";

contract SubAccountManagementTest is MatchingBase {

  function testCanDepositAccount() public {
    uint newAcc = subAccounts.createAccount(cam, pmrm);

    vm.startPrank(cam);
    subAccounts.approve(address(matching), newAcc);
    matching.depositSubAccount(newAcc);
    vm.stopPrank();

    assertEq(subAccounts.ownerOf(newAcc), address(matching));
    assertEq(matching.accountToOwner(newAcc), cam);
  }

  function testCanWithdrawAccount() public {
    // camAcc is already deposited
    vm.startPrank(cam);
    matching.requestWithdrawAccount(camAcc);
    vm.warp(block.timestamp + (1 hours));
    matching.completeWithdrawAccount(camAcc);
    vm.stopPrank();

    assertEq(subAccounts.ownerOf(camAcc), cam);
    assertEq(matching.accountToOwner(camAcc), address(0));
  }

  function testCannotRequestWithdrawFromNonOwner() public {
    vm.expectRevert(SubAccountsManager.M_NotOwnerAddress.selector);

    vm.prank(doug);
    matching.requestWithdrawAccount(camAcc);
  }

  function testCannotWithdrawDuringCooldown() public {
    vm.startPrank(cam);
    matching.requestWithdrawAccount(camAcc);

    vm.expectRevert(abi.encodeWithSelector(SubAccountsManager.M_CooldownNotElapsed.selector, (30 minutes)));

    matching.completeWithdrawAccount(camAcc);
    vm.stopPrank();
  }

  function testCannotCompleteWithWrongSender() public {
    vm.startPrank(cam);
    matching.requestWithdrawAccount(camAcc);
    vm.warp(block.timestamp + (1 hours));
    vm.stopPrank();

    vm.prank(doug);
    vm.expectRevert(SubAccountsManager.M_NotOwnerAddress.selector);
    matching.completeWithdrawAccount(camAcc);
  }
}
