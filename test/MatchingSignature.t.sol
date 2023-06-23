// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {TransferModule} from "src/modules/TransferModule.sol";

/**
 * @notice tests around signature verification
 */
contract MatchingSignatureTest is MatchingBase {
  uint public newKey = 909886112;
  address public newSigner = vm.addr(newKey);

  function testCannotSubmitExpiredOrder() public {
    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(0));
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 minutes, cam, cam, camPk
    );

    vm.warp(block.timestamp + 2 minutes);

    vm.expectRevert(OrderVerifier.M_OrderExpired.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCannotSpecifyWrongOwnerInOrder() public {
    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(0));
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    // change owner to doug
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(depositModule), depositData, block.timestamp + 1 minutes, doug, cam, camPk
    );

    vm.expectRevert(OrderVerifier.M_InvalidOrderOwner.selector);
    _verifyAndMatch(orders, bytes(""));
  }

  function testCanUseSessionKeyToSign() public {
    uint camNewAcc = _createNewAccount(cam);

    vm.startPrank(cam);
    matching.registerSessionKey(newSigner, block.timestamp + 1 days);
    vm.stopPrank();

    OrderVerifier.SignedOrder[] memory orders = _getTransferOrder(camAcc, camNewAcc, cam, newSigner, newKey);

    _verifyAndMatch(orders, "");
  }

  function testCanUseInvalidKey() public {
    uint camNewAcc = _createNewAccount(cam);
    // pretend to be cam
    OrderVerifier.SignedOrder[] memory orders = _getTransferOrder(camAcc, camNewAcc, cam, cam, newKey);

    vm.expectRevert(OrderVerifier.M_InvalidSignature.selector);
    _verifyAndMatch(orders, "");
  }

  function testCannotUseUnDepositedAccount() public {
    vm.startPrank(cam);
    subAccounts.setApprovalForAll(address(matching), true);
    vm.stopPrank();

    uint newCamAcc = subAccounts.createAccount(cam, IManager(address(pmrm)));
    _depositCash(newCamAcc, cashDeposit);

    // specify cam as owner, transfer from new owner to cam
    OrderVerifier.SignedOrder[] memory orders = _getTransferOrder(newCamAcc, camAcc, cam, cam, camPk);

    vm.expectRevert("ERC721: transfer from incorrect owner");
    _verifyAndMatch(orders, "");
  }

  function testDeregisterSessionKey() public {
    vm.startPrank(cam);

    matching.registerSessionKey(newSigner, block.timestamp + 1 days);

    matching.requestDeregisterSessionKey(newSigner);

    vm.warp(block.timestamp + 12 minutes);
    vm.stopPrank();

    uint camNewAcc = _createNewAccount(cam);
    OrderVerifier.SignedOrder[] memory orders = _getTransferOrder(camAcc, camNewAcc, cam, newSigner, newKey);

    vm.expectRevert(OrderVerifier.M_SignerNotOwnerOrSessionKeyExpired.selector);
    _verifyAndMatch(orders, "");
  }

  function testCannotDeregisterInvalidKey() public {
    vm.expectRevert(OrderVerifier.M_SessionKeyInvalid.selector);
    matching.requestDeregisterSessionKey(newSigner);
  }

  function _getTransferOrder(uint from, uint to, address specifiedOwner, address signer, uint pk)
    internal
    returns (OrderVerifier.SignedOrder[] memory)
  {
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    TransferModule.TransferData memory transferData =
      TransferModule.TransferData({toAccountId: to, managerForNewAccount: address(0), transfers: transfers});

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      from, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, specifiedOwner, signer, pk
    );

    return orders;
  }
}
