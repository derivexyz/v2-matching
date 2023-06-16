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
  function testTransfer() public {
    uint newAccountId = subAccounts.createAccount(cam, IManager(address(pmrm)));

    TransferModule.Transfers memory transfer =
      TransferModule.Transfers({asset: address(cash), subId: 0, amount: 1e18});
    TransferModule.Transfers[] memory transfers = new TransferModule.Transfers[](2);
    transfers[0] = transfer;
    transfers[1] = transfer;

    TransferModule.TransferData memory transferData = TransferModule.TransferData({
      toAccountId: newAccountId,
      managerForNewAccount: address(pmrm),
      transfers: transfers
    });

    bytes memory encodedData = abi.encode(transferData);

    OrderVerifier.SignedOrder memory order = _createFullSignedOrder(
      camAcc, 0, address(transferModule), encodedData, block.timestamp + 1 days, cam, cam, camPk
    );

    int camBalBefore = subAccounts.getBalance(newAccountId, cash, 0);

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
    orders[0] = order;
    orders[1] = order;
    _verifyAndMatch(orders, bytes(""));

    int camBalAfter = subAccounts.getBalance(newAccountId, cash, 0);
    int balanceDiff = camBalAfter - camBalBefore;
    console2.log("Balance diff", balanceDiff);
    // Assert balance change
    // assertEq(uint(balanceDiff), withdraw);
  }
}
