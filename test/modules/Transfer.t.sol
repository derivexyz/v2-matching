// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IBaseModule} from "src/interfaces/IBaseModule.sol";
import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";
import {TransferModule, ITransferModule} from "src/modules/TransferModule.sol";

contract TransferModuleTest is MatchingBase {
  function testTransferSingleAsset() public {
    // create a new account
    uint newAccountId = _createNewAccount(cam);

    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData = ITransferModule.TransferData({
      toAccountId: newAccountId,
      managerForNewAccount: address(pmrm),
      transfers: transfers
    });

    // sign order and submit
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      newAccountId, 1, address(transferModule), new bytes(0), block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, bytes(""));

    int newAccAfter = subAccounts.getBalance(newAccountId, cash, 0);
    // Assert balance change
    assertEq(newAccAfter, 1e18);
  }

  function testTransferToNewAccount() public {
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: 0, managerForNewAccount: address(pmrm), transfers: transfers});

    // sign order and submit
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      0, 1, address(transferModule), new bytes(0), block.timestamp + 1 days, cam, cam, camPk
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

    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: -1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
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

    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: -1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    // second order to move the new account to module
    orders[1] =
      _createFullSignedOrder(camNewAcc, 0, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);

    // Repeating nonce causes fail
    vm.expectRevert(IBaseModule.BM_NonceAlreadyUsed.selector);
    _verifyAndMatch(orders, bytes(""));

    orders[1] =
    _createFullSignedOrder(camNewAcc, 1, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);

    // cannot go through because transfer module doesn't have enough allownace
    _verifyAndMatch(orders, bytes(""));

    // debt transferred to camNewAcc
    assertEq(subAccounts.getBalance(camNewAcc, cash, 0), int(cashDeposit) - 1e18);
    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) + 1e18);
  }

  function testCannotAttachInvalidSecondOrder() public {
    uint camNewAcc = _createNewAccount(cam);

    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    // second order is random (signed by another person)
    orders[1] =
      _createFullSignedOrder(dougAcc, 1, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(ITransferModule.TFM_InvalidRecipientOwner.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotTransferToAccountMismatch() public {
    vm.startPrank(cam);
    subAccounts.setApprovalForAll(address(matching), true);
    vm.stopPrank();

    // created but not deposited into matching contract!
    uint camNewAcc = subAccounts.createAccount(cam, IManager(address(pmrm)));

    // specify cam as owner, transfer to newly created account
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});
    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      0, 1, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(ITransferModule.TFM_ToAccountMismatch.selector);
    _verifyAndMatch(orders, "");
  }

  function testCannotCallModuleWithThreeOrders() public {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](3);
    orders[0] =
      _createFullSignedOrder(camAcc, 0, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);
    orders[1] =
      _createFullSignedOrder(dougAcc, 1, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);
    orders[2] = _createFullSignedOrder(0, 2, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(ITransferModule.TFM_InvalidTransferOrderLength.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotTransferFrom0() public {
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    // transfer to doug!!
    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camAcc, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      0, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      camAcc, 1, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(ITransferModule.TFM_InvalidFromAccount.selector);
    _verifyAndMatch(orders, bytes(""));
  }
}
