// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {WithdrawalModule, IWithdrawalModule} from "src/modules/WithdrawalModule.sol";

contract WithdrawalModuleTest is MatchingBase {
  function testWithdraw() public {
    uint withdraw = 12e18;

    // Create signed action for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    (actions[0], signatures[0]) = _createActionAndSign(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, cam, camPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit action
    _verifyAndMatch(actions, signatures, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalBefore - camBalAfter;

    // Assert balance change
    assertEq(uint(balanceDiff), withdraw);
  }

  function testWithdrawWithSigningKey() public {
    uint withdraw = 12e18;

    vm.startPrank(cam);
    matching.registerSessionKey(doug, block.timestamp + 1 weeks);
    vm.stopPrank();

    // Create signed action for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    (actions[0], signatures[0]) = _createActionAndSign(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit action
    _verifyAndMatch(actions, signatures, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalBefore - camBalAfter;

    // Assert balance change
    assertEq(uint(balanceDiff), withdraw);
  }

  function testCannotWithdrawToZeroAccount() public {
    uint withdraw = 12e18;

    // Create signed action for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    (actions[0], signatures[0]) =
      _createActionAndSign(0, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk);

    // Submit action
    vm.expectRevert(IWithdrawalModule.WM_InvalidFromAccount.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }

  function testCannotWithdrawWithMoreThanOneActions() public {
    // Create signed action for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(0, address(cash));

    // Submit action
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);
    (actions[0], signatures[0]) = _createActionAndSign(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk
    );
    (actions[1], signatures[1]) = _createActionAndSign(
      dougAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, doug, doug, dougPk
    );

    vm.expectRevert(IWithdrawalModule.WM_InvalidWithdrawalActionLength.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }
}
