// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {TradeModule, ITradeModule} from "src/modules/TradeModule.sol";

contract TradeModuleTest is MatchingBase {
  // Test trading
  // - Trade from 1 => 1 full limit amount
  // - Trade from 1 taker => 3 maker
  // - Reverts in different cases
  //  - mismatch of signed orders and trade data
  //  - cannot trade if the order is expired

  function testTrade() public {
    IOrderVerifier.SignedOrder[] memory orders = _getDefaultOrders();
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));

    // Assert balance change
    // cam has paid 78 cash and gone long 1 option
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -78e18);
    assertEq(subAccounts.getBalance(camAcc, option, defaultCallId), 1e18);

    // doug has received 78 cash and gone short 1 option
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 78e18);
    assertEq(subAccounts.getBalance(dougAcc, option, defaultCallId), -1e18);
  }

  function testTradeBidAskReversed() public {
    IOrderVerifier.SignedOrder[] memory orders = _getDefaultOrders();
    bytes memory encodedAction = _createMatchedTrade(dougAcc, camAcc, 1e18, 78e18, 0, 0);
    (orders[0], orders[1]) = (orders[1], orders[0]);
    _verifyAndMatch(orders, encodedAction);

    // exact same results, even though maker and taker are swapped

    // Assert balance change
    // cam has paid 78 cash and gone long 1 option
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -78e18);
    assertEq(subAccounts.getBalance(camAcc, option, defaultCallId), 1e18);

    // doug has received 78 cash and gone short 1 option
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 78e18);
    assertEq(subAccounts.getBalance(dougAcc, option, defaultCallId), -1e18);
  }

  function testMultipleFills() public {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](4);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    camTradeData.desiredAmount = 10e18;
    bytes memory camTrade = abi.encode(camTradeData);
    orders[0] =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    ITradeModule.FillDetails[] memory makerFills = new ITradeModule.FillDetails[](3);

    for (uint i = 0; i < 3; i++) {
      ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
      dougTradeData.desiredAmount = 3e18;
      bytes memory dougTrade = abi.encode(dougTradeData);
      orders[i + 1] = _createFullSignedOrder(
        dougAcc, i, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk
      );
      makerFills[i] = ITradeModule.FillDetails({filledAccount: dougAcc, amountFilled: 3e18, price: 78e18, fee: 0});
    }

    bytes memory encodedAction = _createMatchedTrades(camAcc, 0, makerFills);
    _verifyAndMatch(orders, encodedAction);

    // Assert balance change
    // cam has paid 78 cash and gone long 1 option
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -78e18 * 9);
    assertEq(subAccounts.getBalance(camAcc, option, defaultCallId), 9e18);

    // doug has received 78 cash and gone short 1 option
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 78e18 * 9);
    assertEq(subAccounts.getBalance(dougAcc, option, defaultCallId), -9e18);
  }

  function testTradeRevertsWithMismatchedSignedAccounts() public {
    IOrderVerifier.SignedOrder[] memory orders = _getDefaultOrders();
    bytes memory encodedAction = _createMatchedTrade(camAcc, camAcc, 1e18, 78e18, 0, 0);
    vm.expectRevert(ITradeModule.TM_SignedAccountMismatch.selector);
    _verifyAndMatch(orders, encodedAction);
  }

  function testTradeRevertsIfOrderExpired() public {
    IOrderVerifier.SignedOrder[] memory orders = _getDefaultOrders();
    bytes memory encodedAction = _createMatchedTrade(camAcc, camAcc, 1e18, 78e18, 0, 0);
    vm.warp(block.timestamp + 2 days);
    vm.expectRevert(IOrderVerifier.OV_OrderExpired.selector);
    _verifyAndMatch(orders, encodedAction);
  }

  // Test trade price bounds
  // - can trade successfully at two different (txs) prices as long as within the bounds of taker and maker
  // - cannot trade if the bounds are not crossed, even if it satisfies the taker
  // - TODO: perp bounds work the same way

  function testTradeWithinPriceBounds() public {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    camTradeData.worstPrice = 80e18;
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );

    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    dougTradeData.worstPrice = 76e18;
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    // can match within the specified range (can reuse orders too as long as limit isn't crossed)
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 78e18, 0, 0));
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 76e18, 0, 0));
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 80e18, 0, 0));

    vm.expectRevert(ITradeModule.TM_PriceTooHigh.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 81e18, 0, 0));

    vm.expectRevert(ITradeModule.TM_PriceTooLow.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 75e18, 0, 0));

    // Assert balance change
    // cam has paid 78 cash and gone long 1 option
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -78e18 / 10 * 3);
    assertEq(subAccounts.getBalance(camAcc, option, defaultCallId), 0.3e18);

    // doug has received 78 cash and gone short 1 option
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 78e18 / 10 * 3);
    assertEq(subAccounts.getBalance(dougAcc, option, defaultCallId), -0.3e18);
  }

  // Test filling order limits
  // - cannot trade more than the limit
  // - fills are preserved across multiple (txs); limit = 10; fill 4, fill 4, fill 4 (reverts)

  function testTradeCannotExceedLimit() public {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);

    // we try fill 2, with cam's limit being 10 and doug's 1

    camTradeData.desiredAmount = 10e18;
    dougTradeData.desiredAmount = 1e18;

    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(ITradeModule.TM_FillLimitCrossed.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 2e18, 78e18, 0, 0));

    // we try fill 2, but this time roles are reversed

    camTradeData.desiredAmount = 1e18;
    dougTradeData.desiredAmount = 10e18;
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(ITradeModule.TM_FillLimitCrossed.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 2e18, 78e18, 0, 0));

    // works fine if both limits are 10
    camTradeData.desiredAmount = 10e18;
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 2e18, 78e18, 0, 0));
  }

  function testTradeLimitIsPreserved() public {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);

    // we try fill 2, with cam's limit being 10 and doug's 1

    camTradeData.desiredAmount = 10e18;
    dougTradeData.desiredAmount = 20e18;

    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 4e18, 78e18, 0, 0));
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 4e18, 78e18, 0, 0));

    assertEq(tradeModule.filled(cam, 0), 8e18);

    vm.expectRevert(ITradeModule.TM_FillLimitCrossed.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 4e18, 78e18, 0, 0));
  }

  // Test trade fees
  // - trade fees are taken from the maker
  // - trade fees are taken from the taker
  // - trade fees are taken from the maker and taker
  // - reverts if fee limit is crossed

  function testTradeFeesAreSent() public {
    // there is a limit of $1 fee per option in these orders
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    dougTradeData.worstPrice = 0;
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0.3e18, 0));
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0, 0.4e18));
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0.5e18, 0.5e18));

    // trades are matched for 0, so only fees are taken
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -0.8e18);
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), -0.9e18);

    // we try to match again, but this time the fee limit is crossed
    vm.expectRevert(ITradeModule.TM_FeeTooHigh.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0.6e18, 0));
    vm.expectRevert(ITradeModule.TM_FeeTooHigh.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0, 0.6e18));
  }

  // Misc
  // - cannot reuse nonce with different params
  // - can reuse nonce if all trade params are equal (but expiry/signer/etc is different)

  function testCannotReuseNonceWithDiffParams() public {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));

    camTradeData.worstPrice = 79e18;
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(ITradeModule.TM_InvalidNonce.selector);
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));

    camTradeData.worstPrice = 78e18;
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 2 days, cam, cam, camPk
    );
    _verifyAndMatch(orders, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));
  }

  //  function testPerpTrade() public {
  //    mockPerp.setMockPerpPrice(2500e18, 1e18);
  //
  //    ITradeModule.TradeData memory dougTradeData = ITradeModule.TradeData({
  //      asset: address(mockPerp),
  //      subId: 0,
  //      worstPrice: 2502e18,
  //      desiredAmount: 1e18,
  //      worstFee: 1e18,
  //      recipientId: dougAcc,
  //      isBid: true
  //    });
  //    bytes memory dougTrade = abi.encode(dougTradeData);
  //
  //    ITradeModule.TradeData memory camTradeData = ITradeModule.TradeData({
  //      asset: address(mockPerp),
  //      subId: 0,
  //      worstPrice: 2500e18,
  //      desiredAmount: 1e18,
  //      worstFee: 1e18,
  //      recipientId: camAcc,
  //      isBid: false
  //    });
  //    bytes memory camTrade = abi.encode(camTradeData);
  //
  //    IOrderVerifier.SignedOrder memory trade1 =
  //      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
  //    IOrderVerifier.SignedOrder memory trade2 =
  //      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);
  //
  //    // Match data submitted by the orderbook
  //    bytes memory encodedAction = _createMatchedTrade(dougAcc, 0, camAcc, 1e18, 2502e18, 0);
  //
  //    int camBalBefore = subAccounts.getBalance(camAcc, cash, 0);
  //    int dougBalBefore = subAccounts.getBalance(dougAcc, cash, 0);
  //
  //    // Submit Order
  //    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
  //    orders[0] = trade1;
  //    orders[1] = trade2;
  //    _verifyAndMatch(orders, encodedAction);
  //
  //    int camBalAfter = subAccounts.getBalance(camAcc, cash, 0);
  //    int dougBalAfter = subAccounts.getBalance(dougAcc, cash, 0);
  //    int camCashDiff = camBalBefore - camBalAfter;
  //    int dougCashDiff = dougBalBefore - dougBalAfter;
  //
  //    // Assert balance change
  //    assertEq(camCashDiff, -2e18);
  //    assertEq(dougCashDiff, 2e18);
  //  }

  function _getDefaultOrders() internal returns (IOrderVerifier.SignedOrder[] memory) {
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    bytes memory camTrade = abi.encode(camTradeData);
    orders[0] =
      _createFullSignedOrder(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    bytes memory dougTrade = abi.encode(dougTradeData);
    orders[1] =
      _createFullSignedOrder(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    return orders;
  }

  function _getDefaultTrade(uint recipient, bool isBid) internal view returns (ITradeModule.TradeData memory) {
    return ITradeModule.TradeData({
      asset: address(option),
      subId: defaultCallId,
      worstPrice: 78e18,
      desiredAmount: 2e18,
      worstFee: 1e18,
      recipientId: recipient,
      isBid: isBid
    });
  }

  function _createMatchedTrade(
    uint takerAccount,
    uint makerAcc,
    uint amountFilled,
    int price,
    uint takerFee,
    uint makerFee
  ) internal pure returns (bytes memory) {
    ITradeModule.FillDetails memory fillDetails =
      ITradeModule.FillDetails({filledAccount: makerAcc, amountFilled: amountFilled, price: price, fee: makerFee});

    ITradeModule.FillDetails[] memory fills = new ITradeModule.FillDetails[](1);
    fills[0] = fillDetails;

    ITradeModule.ActionData memory actionData = ITradeModule.ActionData({
      takerAccount: takerAccount,
      takerFee: takerFee,
      fillDetails: fills,
      managerData: bytes("")
    });

    bytes memory encodedAction = abi.encode(actionData);
    return encodedAction;
  }

  function _createMatchedTrades(uint takerAccount, uint takerFee, ITradeModule.FillDetails[] memory makerFills)
    internal
    pure
    returns (bytes memory)
  {
    ITradeModule.ActionData memory actionData = ITradeModule.ActionData({
      takerAccount: takerAccount,
      takerFee: takerFee,
      fillDetails: makerFills,
      managerData: bytes("")
    });

    bytes memory encodedAction = abi.encode(actionData);
    return encodedAction;
  }
}
