// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IBaseModule} from "src/interfaces/IBaseModule.sol";
import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
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

    // sign action and submit
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      newAccountId, 1, address(transferModule), new bytes(0), block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(actions, bytes(""));

    int newAccAfter = subAccounts.getBalance(newAccountId, cash, 0);
    // Assert balance change
    assertEq(newAccAfter, 1e18);
  }

  function testTransferToNewAccount() public {
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: 0, managerForNewAccount: address(pmrm), transfers: transfers});

    // sign action and submit
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] =
      _createFullSignedAction(0, 1, address(transferModule), new bytes(0), block.timestamp + 1 days, cam, cam, camPk);

    _verifyAndMatch(actions, bytes(""));

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

    // sign action and submit
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    // cannot go through because transfer module doesn't have enough allownace
    vm.expectRevert();
    _verifyAndMatch(actions, bytes(""));
  }

  function testCanTransferDebtWithSecondAction() public {
    // create a new account to receipt debt
    uint camNewAcc = _createNewAccount(cam);
    _depositCash(camNewAcc, cashDeposit);

    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: -1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    // second action to move the new account to module
    actions[1] =
      _createFullSignedAction(camNewAcc, 0, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);

    // Repeating nonce causes fail
    vm.expectRevert(IBaseModule.BM_NonceAlreadyUsed.selector);
    _verifyAndMatch(actions, bytes(""));

    actions[1] =
      _createFullSignedAction(camNewAcc, 1, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);

    // cannot go through because transfer module doesn't have enough allownace
    _verifyAndMatch(actions, bytes(""));

    // debt transferred to camNewAcc
    assertEq(subAccounts.getBalance(camNewAcc, cash, 0), int(cashDeposit) - 1e18);
    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) + 1e18);
  }

  function testCannotAttachInvalidSecondAction() public {
    uint camNewAcc = _createNewAccount(cam);

    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camNewAcc, managerForNewAccount: address(0), transfers: transfers});

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    // second action is random (signed by another person)
    actions[1] =
      _createFullSignedAction(dougAcc, 1, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(ITransferModule.TFM_InvalidRecipientOwner.selector);
    _verifyAndMatch(actions, bytes(""));
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
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    actions[0] = _createFullSignedAction(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      0, 1, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(ITransferModule.TFM_ToAccountMismatch.selector);
    _verifyAndMatch(actions, "");
  }

  function testCannotCallModuleWithThreeActions() public {
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](3);
    actions[0] =
      _createFullSignedAction(camAcc, 0, address(transferModule), "", block.timestamp + 1 days, cam, cam, camPk);
    actions[1] =
      _createFullSignedAction(dougAcc, 1, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);
    actions[2] =
      _createFullSignedAction(0, 2, address(transferModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(ITransferModule.TFM_InvalidTransferActionLength.selector);
    _verifyAndMatch(actions, bytes(""));
  }

  function testCannotTransferFrom0() public {
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    // transfer to doug!!
    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: camAcc, managerForNewAccount: address(0), transfers: transfers});

    // sign action and submit
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] = _createFullSignedAction(
      0, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      camAcc, 1, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(ITransferModule.TFM_InvalidFromAccount.selector);
    _verifyAndMatch(actions, bytes(""));
  }
}
