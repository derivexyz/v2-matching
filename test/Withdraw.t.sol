// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract WithdrawlModuleTest is MatchingBase {
  function testWithdraw() public {
    uint withdraw = 12e18;

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, cam, camPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalBefore - camBalAfter;

    // Assert balance change
    assertEq(uint(balanceDiff), withdraw);
  }

  // Doug cannot deposit for Cam
  function testCannotWithdrawWithRandomAddress() public {
    uint withdraw = 12e18;

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 days, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;

    vm.expectRevert("signer not permitted, or session key expired for account ID owner");
    _verifyAndMatch(orders, bytes(""));
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
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalBefore - camBalAfter;

    // Assert balance change
    assertEq(uint(balanceDiff), withdraw);
  }

  function testCannotWithdrawWithExpiredSigningKey() public {
    uint withdraw = 12e18;

    vm.startPrank(cam);
    matching.registerSessionKey(doug, block.timestamp + 1 days);
    vm.stopPrank();

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;

    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert("signer not permitted, or session key expired for account ID owner");
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotWithdrawToZeroAccount() public {
    uint withdraw = 12e18;

    // Create signed order for cash withdraw
    bytes memory withdrawData = _encodeWithdrawData(withdraw, address(cash));
    OrderVerifier.SignedOrder memory order =
      _createFullSignedOrder(0, 0, address(withdrawalModule), withdrawData, block.timestamp + 1 weeks, cam, cam, camPk);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;

    vm.expectRevert("Cannot withdraw from zero account");
    _verifyAndMatch(orders, bytes(""));
  }
}
