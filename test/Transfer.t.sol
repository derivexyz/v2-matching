// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {TransferModule} from "src/modules/TransferModule.sol";

contract TransferModuleTest is MatchingBase {
  function testTransferSingleAsset() public {
    // create a new account
    uint newAccountId = _createNewAccount(cam);

    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    TransferModule.TransferData memory transferData = TransferModule.TransferData({
      toAccountId: newAccountId,
      managerForNewAccount: address(pmrm),
      transfers: transfers
    });

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, bytes(""));

    int newAccAfter = subAccounts.getBalance(newAccountId, cash, 0);
    // Assert balance change
    assertEq(newAccAfter, 1e18);
  }

  function testTransferToNewAccount() public {
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: 0, managerForNewAccount: address(pmrm), transfers: transfers});

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, bytes(""));

    uint newAccountId = subAccounts.lastAccountId();
    int newAccAfter = subAccounts.getBalance(newAccountId, cash, 0);
    // Assert balance change
    assertEq(newAccAfter, 1e18);
  }

  function testCannotTransferDebtWithoutAttachingSecondOwner() public {
    // create a new account to receipt debt
    uint camNewAcc = _createNewAccount(cam);
    _depositCash(camNewAcc, cashDeposit);

    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: -1e18});

    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    // cannot go through because transfer module doesn't have enough allownace
    vm.expectRevert();
    _verifyAndMatch(orders, bytes(""));
  }

  function testCanTransferDebtWithSecondOrder() public {
    // create a new account to receipt debt
    uint camNewAcc = _createNewAccount(cam);
    _depositCash(camNewAcc, cashDeposit);

    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: -1e18});

    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    // second order to move the new account to module
    orders[1] =
      _createFullSignedOrder(camNewAcc, 0, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);

    // cannot go through because transfer module doesn't have enough allownace
    _verifyAndMatch(orders, bytes(""));

    // debt transferred to camNewAcc
    assertEq(subAccounts.getBalance(camNewAcc, cash, 0), int(cashDeposit) - 1e18);
    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) + 1e18);
  }

  function testCannotAttachInvalidSecondOrder() public {
    uint camNewAcc = _createNewAccount(cam);

    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    // second order is random (signed by another person)
    orders[1] =
      _createFullSignedOrder(dougAcc, 0, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(TransferModule.TM_InvalidSecondOrder.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotTransferToUnDepositedSubaccount() public {
    vm.startPrank(cam);
    subAccounts.setApprovalForAll(address(matching), true);
    vm.stopPrank();

    // created but not deposited into matching contract!
    uint camNewAcc = subAccounts.createAccount(cam, IManager(address(pmrm)));

    // specify cam as owner, transfer to newly created account
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});
    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(TransferModule.TM_InvalidRecipientOwner.selector);
    _verifyAndMatch(orders, "");
  }

  function testCannotCallModuleWithThreeOrders() public {
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](3);
    orders[0] =
      _createFullSignedOrder(camAcc, 0, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);
    orders[1] =
      _createFullSignedOrder(dougAcc, 0, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);
    orders[2] = _createFullSignedOrder(0, 0, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(TransferModule.TM_InvalidTransferOrderLength.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotTransferBetweenSubAccountsWithDiffUser() public {
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    // transfer to doug!!
    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: dougAcc, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(TransferModule.TM_InvalidRecipientOwner.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotTransferFrom0() public {
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    // transfer to doug!!
    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: dougAcc, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(TransferModule.TM_InvalidRecipientOwner.selector);
    _verifyAndMatch(orders, bytes(""));
  }
}
