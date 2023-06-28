// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";
import {WithdrawalModule, IWithdrawalModule} from "src/modules/WithdrawalModule.sol";

contract WithdrawalModuleTest is MatchingBase {
  function testWithdraw() public {
    uint withdraw = 12e18;

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    IOrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, cam, camPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));

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

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    IOrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalBefore - camBalAfter;

    // Assert balance change
    assertEq(uint(balanceDiff), withdraw);
  }

  function testCannotWithdrawToZeroAccount() public {
    uint withdraw = 12e18;

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    IOrderVerifier.SignedOrder memory order =
      _createFullSignedOrder(0, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    orders[0] = order;

    vm.expectRevert(IWithdrawalModule.WM_InvalidFromAccount.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotWithdrawWithMoreThanOneOrders() public {
    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(0, address(cash));

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, doug, doug, dougPk
    );

    vm.expectRevert(IWithdrawalModule.WM_InvalidWithdrawalOrderLength.selector);
    _verifyAndMatch(orders, bytes(""));
  }
}
