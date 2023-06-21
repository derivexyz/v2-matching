// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {TransferModule} from "src/modules/TransferModule.sol";

contract TransferModuleTest is MatchingBase {
  function testTransferSingleAsset() public {
    // create a new account
    uint newAccountId = subAccounts.createAccount(cam, IManager(address(pmrm)));
    vm.startPrank(cam);
    subAccounts.setApprovalForAll(address(matching), true);
    matching.depositSubAccount(newAccountId);
    vm.stopPrank();

    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    TransferModule.TransferData memory transferData = TransferModule.TransferData({
      toAccountId: newAccountId,
      managerForNewAccount: address(pmrm),
      transfers: transfers
    });

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, bytes(""));

    int newAccAfter = subAccounts.getBalance(newAccountId, cash, 0);
    // Assert balance change
    assertEq(newAccAfter, 1e18);
  }

  function testTransferToNewAccount() public {
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](1);
    transfers[0] = TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});

    TransferModule.TransferData memory transferData = TransferModule.TransferData({
      toAccountId: 0,
      managerForNewAccount: address(pmrm),
      transfers: transfers
    });

    // sign order and submit
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(transferModule), abi.encode(transferData), block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, bytes(""));

    uint newAccountId = subAccounts.lastAccountId();
    int newAccAfter = subAccounts.getBalance(newAccountId, cash, 0);
    // Assert balance change
    assertEq(newAccAfter, 1e18);
  }
}
