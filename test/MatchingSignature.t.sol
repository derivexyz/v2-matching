// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {MatchingBase} from "./shared/MatchingBase.t.sol";
import {TransferModule, ITransferModule} from "src/modules/TransferModule.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";

/**
 * @notice tests around signature verification
 */
contract MatchingSignatureTest is MatchingBase {
  uint public newKey = 909886112;
  address public newSigner = vm.addr(newKey);

  function testCannotSubmitExpiredAction() public {
    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(0));
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);
    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), depositData, block.timestamp + 1 minutes, cam, cam, camPk);

    vm.warp(block.timestamp + 2 minutes);

    vm.expectRevert(IActionVerifier.OV_ActionExpired.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }

  function testCannotSpecifyWrongOwnerInAction() public {
    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(0));
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);
    // change owner to doug
    (actions[0], signatures[0]) = _createActionAndSign(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 minutes, doug, cam, camPk
    );

    vm.expectRevert(IActionVerifier.OV_InvalidActionOwner.selector);
    _verifyAndMatch(actions, signatures, bytes(""));
  }

  function testCanUseSessionKeyToSign() public {
    uint camNewAcc = _createNewAccount(cam);

    vm.startPrank(cam);
    matching.registerSessionKey(newSigner, block.timestamp + 1 days);
    vm.stopPrank();

    (IActionVerifier.Action[] memory actions, bytes[] memory signatures) =
      _getTransferOrder(camAcc, camNewAcc, cam, newSigner, newKey);

    _verifyAndMatch(actions, signatures, "");
  }

  function testCanUseInvalidKey() public {
    uint camNewAcc = _createNewAccount(cam);
    // pretend to be cam
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures) =
      _getTransferOrder(camAcc, camNewAcc, cam, cam, newKey);

    vm.expectRevert(IActionVerifier.OV_InvalidSignature.selector);
    _verifyAndMatch(actions, signatures, "");
  }

  function testCannotUseUnDepositedAccount() public {
    vm.startPrank(cam);
    subAccounts.setApprovalForAll(address(matching), true);
    vm.stopPrank();

    uint newCamAcc = subAccounts.createAccount(cam, IManager(address(pmrm)));
    _depositCash(newCamAcc, cashDeposit);

    // specify cam as owner, transfer from new owner to cam
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures) =
      _getTransferOrder(newCamAcc, camAcc, cam, cam, camPk);

    vm.expectRevert(); // "ERC721: transfer from incorrect owner"
    _verifyAndMatch(actions, signatures, "");
  }

  function testDeregisterSessionKey() public {
    vm.startPrank(cam);

    matching.registerSessionKey(newSigner, block.timestamp + 1 days);

    matching.deregisterSessionKey(newSigner);

    vm.warp(block.timestamp + 12 minutes);
    vm.stopPrank();

    uint camNewAcc = _createNewAccount(cam);
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures) =
      _getTransferOrder(camAcc, camNewAcc, cam, newSigner, newKey);

    vm.expectRevert(IActionVerifier.OV_SignerNotOwnerOrSessionKeyExpired.selector);
    _verifyAndMatch(actions, signatures, "");
  }

  function testCannotDeregisterWithRegisterSessionKeyFunc() public {
    vm.startPrank(cam);

    uint expiry = block.timestamp + 1 days;

    matching.registerSessionKey(newSigner, expiry);

    vm.expectRevert(IActionVerifier.OV_NeedDeregister.selector);
    matching.registerSessionKey(newSigner, expiry - 10 minutes);
  }

  function testCannotDeregisterInvalidKey() public {
    vm.expectRevert(IActionVerifier.OV_SessionKeyInvalid.selector);
    matching.deregisterSessionKey(newSigner);
  }

  function _getTransferOrder(uint from, uint to, address specifiedOwner, address signer, uint pk)
    internal
    view
    returns (IActionVerifier.Action[] memory, bytes[] memory)
  {
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: to, managerForNewAccount: address(0), transfers: transfers});

    // sign action and submit
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);
    (actions[0], signatures[0]) = _createActionAndSign(
      from, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, specifiedOwner, signer, pk
    );
    (actions[1], signatures[1]) = _createActionAndSign(
      to, 1, address(transferModule), new bytes(0), block.timestamp + 1 days, specifiedOwner, signer, pk
    );

    return (actions, signatures);
  }
}
