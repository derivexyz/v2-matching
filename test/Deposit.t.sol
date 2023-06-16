// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract DepositModuleTest is MatchingBase {
  function testDeposit() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);

    // Create signed order for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order =
      _createFullSignedOrder(camAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, cam, camPk);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalAfter - camBalBefore;

    // Assert balance change
    assertEq(uint(balanceDiff), deposit);
  }

  // Doug cannot deposit for Cam
  function testCannotDepositFromRandomAddress() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);

    // Create signed order for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;

    vm.expectRevert("signer not permitted, or session key expired for account ID owner");
    _verifyAndMatch(orders, bytes(""));
  }

  // Doug is able to call deposit on behalf of Cam's account via approved session key
  function testDepositWithSigningKey() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);
    vm.startPrank(cam);
    matching.registerSessionKey(doug, block.timestamp + 1 weeks);
    vm.stopPrank();

    // Create signed order for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalAfter - camBalBefore;

    // Assert balance change
    assertEq(uint(balanceDiff), deposit);
  }

  // Doug CANNOT deposit on behalf of Cam's account due to EXPIRED
  function testCannotDepositWithExpiredSigningKey() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);
    vm.startPrank(cam);
    matching.registerSessionKey(doug, block.timestamp + 1 days);
    vm.stopPrank();

    // Create signed order for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 weeks, cam, doug, dougPk
    );

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert("signer not permitted, or session key expired for account ID owner");
    _verifyAndMatch(orders, bytes(""));
  }

  // If no account Id is specified, deposit into a new account
  function testDepositToNewAccount() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);

    // Create signed order for cash deposit to empty account
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order =
      _createFullSignedOrder(0, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, cam, camPk);

    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    _verifyAndMatch(orders, bytes(""));
    int newAccBal = subAccounts.getBalance(dougAcc + 1, cash, 0);

    // Assert balance change
    assertEq(uint(newAccBal), deposit);
  }
}
