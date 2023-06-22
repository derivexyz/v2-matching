// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {WithdrawalModule} from "src/modules/WithdrawalModule.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract WithdrawalModuleTest is MatchingBase {
  function testWithdraw() public {
    uint withdraw = 12e18;

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, cam, camPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
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
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
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
    OrderVerifier.SignedOrder memory order =
      _createFullSignedOrder(0, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk);

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;

    vm.expectRevert(WithdrawalModule.WM_InvalidFromAccount.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotWithdrawWithMoreThanOneOrders() public {
    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(0, address(cash));

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, doug, doug, dougPk
    );

    vm.expectRevert(WithdrawalModule.WM_InvalidWithdrawalOrderLength.selector);
    _verifyAndMatch(orders, bytes(""));
  }
}
