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
// function testTrade() public {
//   uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);

//   // Doug wants to buy call from cam
//   TradeModule.TradeData memory dougTradeData = TradeModule.TradeData({
//     asset: address(option),
//     subId: callId,
//     worstPrice: 1e18,
//     desiredAmount: 1e18,
//     recipientId: dougAcc
//   });
//   bytes memory dougTrade = abi.encode(dougTradeData);

//   TradeModule.TradeData memory camTradeData = TradeModule.TradeData({
//     asset: address(option),
//     subId: callId,
//     worstPrice: 1e18,
//     desiredAmount: 1e18,
//     recipientId: camAcc
//   });
//   bytes memory camTrade = abi.encode(camTradeData);

//   OrderVerifier.SignedOrder memory trade1 =
//     _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
//   OrderVerifier.SignedOrder memory trade2 =
//     _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

//   // Match data submitted by the orderbook
//   bytes memory encodedMatch = _createMatchData(dougAcc, true, 0, camAcc, 1e18, 1e18, 0);

//   int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
//   int dougBalBefore = subAccounts.getBalance(dougAcc, option, callId);
//   console2.log("dougBefore", dougBalBefore);
//   // Submit Order
//   OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
//   orders[0] = trade1;
//   orders[1] = trade2;
//   _verifyAndMatch(orders, encodedMatch);

//   int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
//   int dougBalAfter = subAccounts.getBalance(dougAcc, option, callId);
//   int camCashDiff = camBalAfter - camBalBefore;
//   int dougOptionDiff = dougBalAfter - dougBalBefore;
//   console2.log("dougAfter", dougBalAfter);
//   console2.log("Balance diff", camCashDiff);
//   console2.log("Balance diff", dougOptionDiff);

//   // Assert balance change
//   assertEq(uint(camCashDiff), 1e18);
//   // assertEq(uint(dougOptionDiff), -1e18); // todo call should be +?
// }

// function testCannotTradeHighPrice() public {
//   uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);

//   TradeModule.TradeData memory dougTradeData = TradeModule.TradeData({
//     asset: address(option),
//     subId: callId,
//     worstPrice: 1e18,
//     desiredAmount: 1e18,
//     recipientId: dougAcc
//   });
//   bytes memory dougTrade = abi.encode(dougTradeData);

//   TradeModule.TradeData memory camTradeData = TradeModule.TradeData({
//     asset: address(option),
//     subId: callId,
//     worstPrice: 1e18,
//     desiredAmount: 1e18,
//     recipientId: camAcc
//   });
//   bytes memory camTrade = abi.encode(camTradeData);

//   OrderVerifier.SignedOrder memory trade1 =
//     _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
//   OrderVerifier.SignedOrder memory trade2 =
//     _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

//   // Match data submitted by the orderbook
//   bytes memory encodedMatch = _createMatchData(dougAcc, true, 0, camAcc, 1e18, 2e18, 0);

//   int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
//   int dougBalBefore = subAccounts.getBalance(dougAcc, option, callId);
//   console2.log("dougBefore", dougBalBefore);

//   // Submit Order
//   OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
//   orders[0] = trade1;
//   orders[1] = trade2;

//   // Doug price 1, cam price 1/10
//   vm.expectRevert("price too high");
//   _verifyAndMatch(orders, encodedMatch);
// }

// function testCannotTradeLowPrice() public {
//   uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);

//   TradeModule.TradeData memory dougTradeData = TradeModule.TradeData({
//     asset: address(option),
//     subId: callId,
//     worstPrice: 1e18,
//     desiredAmount: 10e18,
//     recipientId: dougAcc
//   });
//   bytes memory dougTrade = abi.encode(dougTradeData);

//   TradeModule.TradeData memory camTradeData = TradeModule.TradeData({
//     asset: address(option),
//     subId: callId,
//     worstPrice: 10e18,
//     desiredAmount: 10e18,
//     recipientId: camAcc
//   });
//   bytes memory camTrade = abi.encode(camTradeData);

//   OrderVerifier.SignedOrder memory trade1 =
//     _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
//   OrderVerifier.SignedOrder memory trade2 =
//     _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

//   // Match data submitted by the orderbook
//   bytes memory encodedMatch = _createMatchData(dougAcc, true, 0, camAcc, 1e18, 1e18, 0);

//   int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
//   int dougBalBefore = subAccounts.getBalance(dougAcc, option, callId);
//   console2.log("dougBefore", dougBalBefore);

//   // Submit Order
//   OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
//   orders[0] = trade1;
//   orders[1] = trade2;

//   // doug price 1/10, cam price 1
//   vm.expectRevert("price too low");
//   _verifyAndMatch(orders, encodedMatch);
// }

// function _createMatchData(
//   uint matchedAccount,
//   bool isBidder,
//   uint matcherFee,
//   uint filledAcc,
//   uint amountFilled,
//   int price,
//   uint fee
// ) internal returns (bytes memory) {
//   TradeModule.FillDetails memory fillDetails =
//     TradeModule.FillDetails({filledAccount: filledAcc, amountFilled: amountFilled, price: price, fee: fee});

//   TradeModule.FillDetails[] memory fills = new TradeModule.FillDetails[](1);
//   fills[0] = fillDetails;

//   TradeModule.MatchData memory matchData = TradeModule.MatchData({
//     matchedAccount: matchedAccount,
//     isBidder: isBidder,
//     matcherFee: matcherFee,
//     fillDetails: fills,
//     managerData: bytes("")
//   });

//   bytes memory encodedMatch = abi.encode(matchData);
//   return encodedMatch;
// }
}
