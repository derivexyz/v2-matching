// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {TradeModule, ITradeModule} from "src/modules/TradeModule.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

contract TradeModuleTest is MatchingBase {
  // Test trading
  // - Trade from 1 => 1 full limit amount
  // - Trade from 1 taker => 3 maker
  // - Reverts in different cases
  //  - mismatch of signed orders and trade data
  //  - cannot trade if the order is expired
  //  -
  // Test trade price bounds
  // - can trade successfully at two different (txs) prices as long as within the bounds of taker and maker
  // - cannot trade if the bounds are not crossed, even if it satisfies the taker
  // - perp bounds work the same way
  // Test filling order limits
  // - cannot trade more than the limit
  // - fills are preserved across multiple (txs); limit = 10; fill 4, fill 4, fill 4 (reverts)
  // Test trade fees
  // - trade fees are taken from the maker
  // - trade fees are taken from the taker
  // - trade fees are taken from the maker and taker
  // - reverts if fee limit is crossed
  // Misc
  // - cannot reuse nonce with different params
  // - can reuse nonce if all params are equal (but expiry is different)

  function testTrade() public {
    uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);
    // Doug wants to buy call from cam
    ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 1e18,
      desiredAmount: 1e18,
      worstFee: 1e18,
      recipientId: dougAcc,
      isBid: true
    });
    bytes memory dougTrade = abi.encode(dougTradeData);

    bytes memory camTrade;
    {
      ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
        asset: address(option),
        subId: callId,
        worstPrice: 1e18,
        desiredAmount: 1e18,
        worstFee: 1e18,
        recipientId: camAcc,
        isBid: false
      });
      camTrade = abi.encode(camTradeData);
    }

    IOrderVerifier.SignedOrder memory trade1 =
      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    IOrderVerifier.SignedOrder memory trade2 =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    // Match data submitted by the orderbook
    bytes memory encodedAction = _createActionData(dougAcc, 0, camAcc, 1e18, 1e18, 0);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    int dougBalBefore = subAccounts.getBalance(dougAcc, option, callId);
    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = trade1;
    orders[1] = trade2;
    _verifyAndMatch(orders, encodedAction);

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int dougBalAfter = subAccounts.getBalance(dougAcc, option, callId);
    int camCashDiff = camBalAfter - camBalBefore;
    int dougOptionDiff = dougBalAfter - dougBalBefore;

    // Assert balance change
    assertEq(uint(camCashDiff), 1e18);
    assertEq(uint(dougOptionDiff), 1e18);
  }

  // function testOneToManyTrade() public {
  //   uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);

  //   // Doug wants to buy call from cam
  //   ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
  //     asset: address(option),
  //     subId: callId,
  //     worstPrice: 1e18,
  //     desiredAmount: 10e18,
  //     recipientId: dougAcc
  //   });
  //   bytes memory dougTrade = abi.encode(dougTradeData);

  //   ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
  //     asset: address(option),
  //     subId: callId,
  //     worstPrice: 1e18,
  //     desiredAmount: 1e18,
  //     recipientId: camAcc
  //   });
  //   bytes memory camTrade = abi.encode(camTradeData);

  //   ITradeModule.TradeData memory camTradeData2 = ITradeModule.TradeData({
  //     asset: address(option),
  //     subId: callId,
  //     worstPrice: 1e18,
  //     desiredAmount: 1e18,
  //     recipientId: camAcc
  //   });
  //   bytes memory camTrade2 = abi.encode(camTradeData)2;

  //   IOrderVerifier.SignedOrder memory trade1 =
  //     _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
  //   IOrderVerifier.SignedOrder memory trade2 =
  //     _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);
  //   IOrderVerifier.SignedOrder memory trade3 =
  //     _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

  //   // Match data submitted by the orderbook
  //   bytes memory encodedAction = _createActionData(dougAcc, 0, camAcc, 1e18, 1e18, 0); //todo match data for many fills

  //   int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
  //   int dougBalBefore = subAccounts.getBalance(dougAcc, option, callId);
  //   console2.log("dougBefore", dougBalBefore);
  //   // Submit Order
  //   IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
  //   orders[0] = trade1;
  //   orders[1] = trade2;
  //   _verifyAndMatch(orders, encodedAction);

  //   int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
  //   int dougBalAfter = subAccounts.getBalance(dougAcc, option, callId);
  //   int camCashDiff = camBalAfter - camBalBefore;
  //   int dougOptionDiff = dougBalAfter - dougBalBefore;
  //   console2.log("dougAfter", dougBalAfter);
  //   console2.log("Balance diff", camCashDiff);
  //   console2.log("Balance diff", dougOptionDiff);

  //   // Assert balance change
  //   assertEq(uint(camCashDiff), 1e18);
  //   assertEq(uint(dougOptionDiff), 1e18);
  // }

  function testFillAmount() public {
    uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);

    // Doug wants to buy call from cam
    ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 1e18,
      desiredAmount: 10e18,
      worstFee: 1e18,
      recipientId: dougAcc,
      isBid: true
    });
    bytes memory dougTrade = abi.encode(dougTradeData);

    ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 1e18,
      desiredAmount: 10e18,
      worstFee: 1e18,
      recipientId: camAcc,
      isBid: false
    });
    bytes memory camTrade = abi.encode(camTradeData);

    IOrderVerifier.SignedOrder memory trade1 =
      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    IOrderVerifier.SignedOrder memory trade2 =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    // Match data submitted by the orderbook
    bytes memory encodedAction = _createActionData(dougAcc, 0, camAcc, 1e18, 1e18, 0);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = trade1;
    orders[1] = trade2;
    _verifyAndMatch(orders, encodedAction);
    assertEq(tradeModule.filled(doug, 0), 1e18);

    _verifyAndMatch(orders, encodedAction);
    assertEq(tradeModule.filled(doug, 0), 1e18 * 2);
  }

  function testCannotTradeHighPrice() public {
    uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);
    ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 1e18,
      desiredAmount: 1e18,
      worstFee: 1e18,
      recipientId: dougAcc,
      isBid: true
    });
    bytes memory dougTrade = abi.encode(dougTradeData);

    ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 1e18,
      desiredAmount: 1e18,
      worstFee: 1e18,
      recipientId: camAcc,
      isBid: false
    });
    bytes memory camTrade = abi.encode(camTradeData);

    IOrderVerifier.SignedOrder memory trade1 =
      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    IOrderVerifier.SignedOrder memory trade2 =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    // Match data submitted by the orderbook
    bytes memory encodedAction = _createActionData(dougAcc, 0, camAcc, 1e18, 2e18, 0);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = trade1;
    orders[1] = trade2;

    // Doug price 1, cam price 1/10
    vm.expectRevert("price too high");
    _verifyAndMatch(orders, encodedAction);
  }

  function testCannotTradeLowPrice() public {
    uint callId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);
    ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 1e18,
      desiredAmount: 10e18,
      worstFee: 1e18,
      recipientId: dougAcc,
      isBid: true
    });
    bytes memory dougTrade = abi.encode(dougTradeData);

    ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
      asset: address(option),
      subId: callId,
      worstPrice: 10e18,
      desiredAmount: 10e18,
      worstFee: 1e18,
      recipientId: camAcc,
      isBid: false
    });
    bytes memory camTrade = abi.encode(camTradeData);

    IOrderVerifier.SignedOrder memory trade1 =
      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    IOrderVerifier.SignedOrder memory trade2 =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    // Match data submitted by the orderbook
    bytes memory encodedAction = _createActionData(dougAcc, 0, camAcc, 1e18, 1e18, 0);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = trade1;
    orders[1] = trade2;

    // doug price 1/10, cam price 1
    vm.expectRevert("price too low");
    _verifyAndMatch(orders, encodedAction);
  }

  function testPerpTrade() public {
    mockPerp.setMockPerpPrice(2500e18, 1e18);

    ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
      asset: address(mockPerp),
      subId: 0,
      worstPrice: 2502e18,
      desiredAmount: 1e18,
      worstFee: 1e18,
      recipientId: dougAcc,
      isBid: true
    });
    bytes memory dougTrade = abi.encode(dougTradeData);

    ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
      asset: address(mockPerp),
      subId: 0,
      worstPrice: 2500e18,
      desiredAmount: 1e18,
      worstFee: 1e18,
      recipientId: camAcc,
      isBid: false
    });
    bytes memory camTrade = abi.encode(camTradeData);

    IOrderVerifier.SignedOrder memory trade1 =
      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    IOrderVerifier.SignedOrder memory trade2 =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    // Match data submitted by the orderbook
    bytes memory encodedAction = _createActionData(dougAcc, 0, camAcc, 1e18, 2502e18, 0);

    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
    int dougBalBefore = subAccounts.getBalance(dougAcc, cash, 0);

    // Submit Order
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = trade1;
    orders[1] = trade2;
    _verifyAndMatch(orders, encodedAction);

    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
    int dougBalAfter = subAccounts.getBalance(dougAcc, cash, 0);
    int camCashDiff = camBalBefore - camBalAfter;
    int dougCashDiff = dougBalBefore - dougBalAfter;

    // Assert balance change
    assertEq(camCashDiff, -2e18);
    assertEq(dougCashDiff, 2e18);
  }

  function _createActionData(uint takerAccount, uint matcherFee, uint makerAcc, uint amountFilled, int price, uint fee)
    internal
    pure
    returns (bytes memory)
  {
    ITradeModule.FillDetails memory fillDetails = ITradeModule.FillDetails({
      filledAccount: makerAcc,
      amountFilled: amountFilled,
      price: price,
      fee: fee,
      perpDelta: 0
    });

    ITradeModule.FillDetails[] memory fills = new ITradeModule.FillDetails[](1);
    fills[0] = fillDetails;

    ITradeModule.ActionData memory actionData = ITradeModule.ActionData({
      takerAccount: takerAccount,
      takerFee: matcherFee,
      fillDetails: fills,
      managerData: bytes("")
    });

    bytes memory encodedAction = abi.encode(actionData);
    return encodedAction;
  }
}
