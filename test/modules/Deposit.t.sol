// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {DepositModule, IDepositModule} from "src/modules/DepositModule.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract DepositModuleTest is MatchingBase {
  function testDeposit() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);

    // Create signed action for cash deposit
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, cam, camPk);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit actions
    _verifyAndMatch(actions, signatures, bytes(""));

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalAfter - camBalBefore;

    // Assert balance change
    assertEq(uint(balanceDiff), deposit);
  }

  function testCannotCallDepositWithWrongActionLength() public {
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);
    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), "", block.timestamp + 1 days, cam, cam, camPk);
    (actions[1], signatures[1]) =
      _createActionAndSign(dougAcc, 0, address(depositModule), "", block.timestamp + 1 days, doug, doug, dougPk);

    vm.expectRevert(IDepositModule.DM_InvalidDepositActionLength.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }

  // Doug cannot deposit for Cam
  function testCannotDepositWithRandomAddress() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);

    // Create signed action for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));

    bytes[] memory signatures = new bytes[](1);
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);

    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, doug, dougPk);

    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    vm.expectRevert(IActionVerifier.OV_SignerNotOwnerOrSessionKeyExpired.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }

  // Doug is able to call deposit on behalf of Cam's account via approved session key
  function testDepositWithSigningKey() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);
    vm.startPrank(cam);
    matching.registerSessionKey(doug, block.timestamp + 1 weeks);
    vm.stopPrank();

    // Create signed action for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, doug, dougPk);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit action
    _verifyAndMatch(actions, signatures, bytes(""));

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

    // Create signed action for cash deposit
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), depositData, block.timestamp + 1 weeks, cam, doug, dougPk);

    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit action

    vm.warp(block.timestamp + 1 days + 1);
    vm.expectRevert(IActionVerifier.OV_SignerNotOwnerOrSessionKeyExpired.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }

  // If no account Id is specified, deposit into a new account
  function testDepositToNewAccount() public {
    uint deposit = 1e18;
    usdc.mint(cam, deposit);

    // Create signed action for cash deposit to empty account
    bytes memory depositData = _encodeDepositData(deposit, address(cash), address(pmrm));

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    (actions[0], signatures[0]) =
      _createActionAndSign(0, 0, address(depositModule), depositData, block.timestamp + 1 days, cam, cam, camPk);

    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();
    vm.startPrank(cam);
    cashToken.approve(address(depositModule), deposit);
    vm.stopPrank();

    // Submit action
    _verifyAndMatch(actions, signatures, bytes(""));
    int newAccBal = subAccounts.getBalance(dougAcc + 1, cash, 0);

    // Assert balance change
    assertEq(uint(newAccBal), deposit);
  }

  // testing shared function in BaseModule

  function testCanSendERC20Out() public {
    uint stuckAmount = 1000e6;
    uint usdcBefore = usdc.balanceOf(address(this));
    usdc.mint(address(depositModule), stuckAmount);

    depositModule.withdrawERC20(address(usdc), address(this), stuckAmount);

    assertEq(usdc.balanceOf(address(this)), usdcBefore + stuckAmount);
    assertEq(usdc.balanceOf(address(depositModule)), 0);
  }
}
