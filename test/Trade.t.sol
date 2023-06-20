// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {TradeModule} from "src/modules/TradeModule.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

contract TradeModuleTest is MatchingBase {
  function testTrade() public {
    // Doug wants to buy call from cam
    TradeModule.FillDetails memory fill1 =
      TradeModule.FillDetails({filledAccount: camAcc, amountFilled: 1e18, price: 1e18, fee: 0});
    TradeModule.FillDetails[] memory fills = new TradeModule.FillDetails[](1);
    fills[0] = fill1;

    TradeModule.MatchData memory matched = TradeModule.MatchData({
      matchedAccount: camAcc,
      isBidder: false,
      matcherFee: 0,
      fillDetails: fills,
      managerData: bytes("")
    });
    bytes memory matchData = abi.encode(matched);

    uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);
    TradeModule.TradeData memory tradeData = TradeModule.TradeData({asset: address(option), subId: callId, worstPrice: 5e18, desiredAmount: 10e18, recipientId: dougAcc});
    bytes memory encodedTrade = abi.encode(tradeData);

    OrderVerifier.SignedOrder memory trade =
      // _createFullSignedOrder(dougAcc, 0, address(tradeModule), encodedTrade, block.timestamp + 1 days, doug, doug, dougPk);
      _createFullSignedOrder(camAcc, 0, address(tradeModule), encodedTrade, block.timestamp + 1 days, cam, cam, camPk);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);

    // Submit Order
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = trade;
  
    _verifyAndMatch(orders, matchData);

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int balanceDiff = camBalAfter - camBalBefore;
    console2.log("Balance diff", balanceDiff);
    // Assert balance change
    // assertEq(uint(balanceDiff), withdraw);
  }
}
