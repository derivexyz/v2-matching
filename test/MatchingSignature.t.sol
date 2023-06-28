// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {MatchingBase} from "./shared/MatchingBase.t.sol";
import {TransferModule, ITransferModule} from "src/modules/TransferModule.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";

/**
 * @notice tests around signature verification
 */
contract MatchingSignatureTest is MatchingBase {
  uint public newKey = 909886112;
  address public newSigner = vm.addr(newKey);

  function testCannotSubmitExpiredOrder() public {
    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(0));
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 minutes, cam, cam, camPk
    );

    vm.warp(block.timestamp + 2 minutes);

    vm.expectRevert(IOrderVerifier.OV_OrderExpired.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotSpecifyWrongOwnerInOrder() public {
    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(0));
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    // change owner to doug
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 minutes, doug, cam, camPk
    );

    vm.expectRevert(IOrderVerifier.OV_InvalidOrderOwner.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCanUseSessionKeyToSign() public {
    uint camNewAcc = _createNewAccount(cam);

    vm.startPrank(cam);
    matching.registerSessionKey(newSigner, block.timestamp + 1 days);
    vm.stopPrank();

    IOrderVerifier.SignedOrder[] memory orders = _getTransferOrder(camAcc, camNewAcc, cam, newSigner, newKey);

    _verifyAndMatch(orders, "");
  }

  function testCanUseInvalidKey() public {
    uint camNewAcc = _createNewAccount(cam);
    // pretend to be cam
    IOrderVerifier.SignedOrder[] memory orders = _getTransferOrder(camAcc, camNewAcc, cam, cam, newKey);

    vm.expectRevert(IOrderVerifier.OV_InvalidSignature.selector);
    _verifyAndMatch(orders, "");
  }

  function testCannotUseUnDepositedAccount() public {
    vm.startPrank(cam);
    subAccounts.setApprovalForAll(address(matching), true);
    vm.stopPrank();

    uint newCamAcc = subAccounts.createAccount(cam, IManager(address(pmrm)));
    _depositCash(newCamAcc, cashDeposit);

    // specify cam as owner, transfer from new owner to cam
    IOrderVerifier.SignedOrder[] memory orders = _getTransferOrder(newCamAcc, camAcc, cam, cam, camPk);

    vm.expectRevert("ERC721: transfer from incorrect owner");
    _verifyAndMatch(orders, "");
  }

  function testDeregisterSessionKey() public {
    vm.startPrank(cam);

    matching.registerSessionKey(newSigner, block.timestamp + 1 days);

    matching.deregisterSessionKey(newSigner);

    vm.warp(block.timestamp + 12 minutes);
    vm.stopPrank();

    uint camNewAcc = _createNewAccount(cam);
    IOrderVerifier.SignedOrder[] memory orders = _getTransferOrder(camAcc, camNewAcc, cam, newSigner, newKey);

    vm.expectRevert(IOrderVerifier.OV_SignerNotOwnerOrSessionKeyExpired.selector);
    _verifyAndMatch(orders, "");
  }

  function testCannotDeregisterInvalidKey() public {
    vm.expectRevert(IOrderVerifier.OV_SessionKeyInvalid.selector);
    matching.deregisterSessionKey(newSigner);
  }

  function _getTransferOrder(uint from, uint to, address specifiedOwner, address signer, uint pk)
    internal
    view
    returns (IOrderVerifier.SignedOrder[] memory)
  {
    ITransferModule.Transfers[] memory transfers = new ITransferModule.Transfers[](1);
    transfers[0] = ITransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    ITransferModule.TransferData memory transferData =
      ITransferModule.TransferData({toAccountId: to, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      from, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, specifiedOwner, signer, pk
    );
    orders[1] = _createFullSignedOrder(
      to, 1, address(transferModule), new bytes(0), block.timestamp + 1 days, specifiedOwner, signer, pk
    );

    return orders;
  }
}
