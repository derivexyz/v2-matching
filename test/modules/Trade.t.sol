// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {TradeModule, ITradeModule} from "src/modules/TradeModule.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {MockDataReceiver} from "../mock/MockDataReceiver.sol";

contract TradeModuleTest is MatchingBase {
  // Test trading
  // - Trade from 1 => 1 full limit amount
  // - Trade from 1 taker => 3 maker
  // - Reverts in different cases
  //  - mismatch of signed actions and trade data
  //  - cannot trade if the order is expired

  function testSetFeeRecipient() public {
    uint newAcc = subAccounts.createAccount(cam, pmrm);
    tradeModule.setFeeRecipient(newAcc);
    assertEq(tradeModule.feeRecipient(), newAcc);
  }

  function testSetIsPerp() public {
    tradeModule.setPerpAsset(IPerpAsset(address(this)), true);
    assertEq(tradeModule.isPerpAsset(IPerpAsset(address(this))), true);
  }

  ////////////////////////
  //     Test Trades    //
  ////////////////////////

  function testTrade() public {
    IActionVerifier.Action[] memory actions = _getDefaultActions();
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));

    // Assert balance change
    // cam has paid 78 cash and gone long 1 option
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -78e18);
    assertEq(subAccounts.getBalance(camAcc, option, defaultCallId), 1e18);

    // doug has received 78 cash and gone short 1 option
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 78e18);
    assertEq(subAccounts.getBalance(dougAcc, option, defaultCallId), -1e18);
  }

  function testTradeBidAskReversed() public {
    IActionVerifier.Action[] memory actions = _getDefaultActions();
    bytes memory encodedAction = _createMatchedTrade(dougAcc, camAcc, 1e18, 78e18, 0, 0);
    (actions[0], actions[1]) = (actions[1], actions[0]);
    _verifyAndMatch(actions, encodedAction);

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
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](4);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    camTradeData.desiredAmount = 10e18;
    bytes memory camTrade = abi.encode(camTradeData);
    actions[0] =
      _createFullSignedAction(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    ITradeModule.FillDetails[] memory makerFills = new ITradeModule.FillDetails[](3);

    for (uint i = 0; i < 3; i++) {
      ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
      dougTradeData.desiredAmount = 3e18;
      bytes memory dougTrade = abi.encode(dougTradeData);
      actions[i + 1] = _createFullSignedAction(
        dougAcc, i, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk
      );
      makerFills[i] = ITradeModule.FillDetails({filledAccount: dougAcc, amountFilled: 3e18, price: 78e18, fee: 0});
    }

    bytes memory encodedAction = _createMatchedTrades(camAcc, 0, makerFills);
    _verifyAndMatch(actions, encodedAction);

    // Assert balance change
    // cam has paid 78 cash and gone long 1 option
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -78e18 * 9);
    assertEq(subAccounts.getBalance(camAcc, option, defaultCallId), 9e18);

    // doug has received 78 cash and gone short 1 option
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 78e18 * 9);
    assertEq(subAccounts.getBalance(dougAcc, option, defaultCallId), -9e18);
  }

  function testTradeRevertsWithMismatchedSignedAccounts() public {
    IActionVerifier.Action[] memory actions = _getDefaultActions();
    bytes memory encodedAction = _createMatchedTrade(camAcc, camAcc, 1e18, 78e18, 0, 0);
    vm.expectRevert(ITradeModule.TM_SignedAccountMismatch.selector);
    _verifyAndMatch(actions, encodedAction);
  }

  function testTradeRevertsIfActionExpired() public {
    IActionVerifier.Action[] memory actions = _getDefaultActions();
    bytes memory encodedAction = _createMatchedTrade(camAcc, camAcc, 1e18, 78e18, 0, 0);
    vm.warp(block.timestamp + 2 days);
    vm.expectRevert(IActionVerifier.OV_ActionExpired.selector);
    _verifyAndMatch(actions, encodedAction);
  }

  // Test trade price bounds
  // - can trade successfully at two different (txs) prices as long as within the bounds of taker and maker
  // - cannot trade if the bounds are not crossed, even if it satisfies the taker
  // - TODO: perp bounds work the same way

  function testTradeWithinPriceBounds() public {
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    camTradeData.limitPrice = 80e18;
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );

    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    dougTradeData.limitPrice = 76e18;
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    // can match within the specified range (can reuse actions too as long as limit isn't crossed)
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 78e18, 0, 0));
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 76e18, 0, 0));
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 80e18, 0, 0));

    vm.expectRevert(ITradeModule.TM_PriceTooHigh.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 81e18, 0, 0));

    vm.expectRevert(ITradeModule.TM_PriceTooLow.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.1e18, 75e18, 0, 0));

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
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);

    // we try fill 2, with cam's limit being 10 and doug's 1

    camTradeData.desiredAmount = 10e18;
    dougTradeData.desiredAmount = 1e18;

    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(ITradeModule.TM_FillLimitCrossed.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 2e18, 78e18, 0, 0));

    // we try fill 2, but this time roles are reversed

    camTradeData.desiredAmount = 1e18;
    dougTradeData.desiredAmount = 10e18;
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(ITradeModule.TM_FillLimitCrossed.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 2e18, 78e18, 0, 0));

    // works fine if both limits are 10
    camTradeData.desiredAmount = 10e18;
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 2e18, 78e18, 0, 0));
  }

  function testTradeLimitIsPreserved() public {
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);

    // we try fill 2, with cam's limit being 10 and doug's 1

    camTradeData.desiredAmount = 10e18;
    dougTradeData.desiredAmount = 20e18;

    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 4e18, 78e18, 0, 0));
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 4e18, 78e18, 0, 0));

    assertEq(tradeModule.filled(cam, 0), 8e18);

    vm.expectRevert(ITradeModule.TM_FillLimitCrossed.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 4e18, 78e18, 0, 0));
  }

  // Test trade fees
  // - trade fees are taken from the maker
  // - trade fees are taken from the taker
  // - trade fees are taken from the maker and taker
  // - reverts if fee limit is crossed

  function testTradeFeesAreSent() public {
    // there is a limit of $1 fee per option in these actions
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    dougTradeData.limitPrice = 0;
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0.3e18, 0));
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0, 0.4e18));
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0.5e18, 0.5e18));

    // trades are matched for 0, so only fees are taken
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -0.8e18);
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), -0.9e18);

    // we try to match again, but this time the fee limit is crossed
    vm.expectRevert(ITradeModule.TM_FeeTooHigh.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0.6e18, 0));
    vm.expectRevert(ITradeModule.TM_FeeTooHigh.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 0.5e18, 0, 0, 0.6e18));
  }

  // Misc
  // - cannot reuse nonce with different params
  // - can reuse nonce if all trade params are equal (but expiry/signer/etc is different)

  function testCannotReuseNonceWithDiffParams() public {
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(tradeModule), abi.encode(dougTradeData), block.timestamp + 1 days, doug, doug, dougPk
    );

    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));

    camTradeData.limitPrice = 79e18;
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 1 days, cam, cam, camPk
    );

    vm.expectRevert(ITradeModule.TM_InvalidNonce.selector);
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));

    camTradeData.limitPrice = 78e18;
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(tradeModule), abi.encode(camTradeData), block.timestamp + 2 days, cam, cam, camPk
    );
    _verifyAndMatch(actions, _createMatchedTrade(camAcc, dougAcc, 1e18, 78e18, 0, 0));
  }

  function testPerpTrade() public {
    mockPerp.setMockPerpPrice(2500e18, 1e18);

    bytes memory camTrade = abi.encode(
      ITradeModule.TradeData({
        asset: address(mockPerp),
        subId: 0,
        limitPrice: 2502e18,
        desiredAmount: 1e18,
        worstFee: 1e18,
        recipientId: camAcc,
        isBid: true
      })
    );

    bytes memory dougTrade = abi.encode(
      ITradeModule.TradeData({
        asset: address(mockPerp),
        subId: 0,
        limitPrice: 2502e18,
        desiredAmount: 1e18,
        worstFee: 1e18,
        recipientId: dougAcc,
        isBid: false
      })
    );

    // Submit Order
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] =
      _createFullSignedAction(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);
    actions[1] =
      _createFullSignedAction(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);

    // perpPrice is 2500, they match at 2502, so only $2 should be transferred for the perp
    bytes memory encodedAction = _createMatchedTrade(camAcc, dougAcc, 1e18, 2502e18, 0, 0);
    _verifyAndMatch(actions, encodedAction);

    // Assert balance change
    assertEq(subAccounts.getBalance(camAcc, cash, 0) - int(cashDeposit), -2e18);
    assertEq(subAccounts.getBalance(camAcc, mockPerp, 0), 1e18);
    assertEq(subAccounts.getBalance(dougAcc, cash, 0) - int(cashDeposit), 2e18);
    assertEq(subAccounts.getBalance(dougAcc, mockPerp, 0), -1e18);
  }

  function testCanUpdateSpotAndThenTrade() public {
    MockDataReceiver mockedUpdater = new MockDataReceiver();
    pmrm.setWhitelistedCallee(address(mockedUpdater), true);
    uint newPrice = 2000;

    // use the default actions
    IActionVerifier.Action[] memory actions = _getDefaultActions();

    // fill in default fill details
    ITradeModule.FillDetails[] memory fills = new ITradeModule.FillDetails[](1);
    fills[0] = ITradeModule.FillDetails({filledAccount: dougAcc, amountFilled: 1e18, price: 78e18, fee: 0});

    // the data that should be processed before trade
    IBaseManager.ManagerData[] memory managerDatas = new IBaseManager.ManagerData[](1);
    bytes memory receiverData = abi.encode(address(feed), newPrice);
    managerDatas[0] = IBaseManager.ManagerData(address(mockedUpdater), receiverData);
    bytes memory finalManagerData = abi.encode(managerDatas);

    ITradeModule.OrderData memory orderData =
      ITradeModule.OrderData({takerAccount: camAcc, takerFee: 0, fillDetails: fills, managerData: finalManagerData});

    bytes memory matchData = abi.encode(orderData);

    _verifyAndMatch(actions, matchData);

    (uint newSpot,) = feed.getSpot();
    assertEq(newSpot, newPrice);
  }

  /// @dev return order of 2: [0: cam (taker)], [1: doug (maker)]
  function _getDefaultActions() internal view returns (IActionVerifier.Action[] memory) {
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);

    ITradeModule.TradeData memory camTradeData = _getDefaultTrade(camAcc, true);
    bytes memory camTrade = abi.encode(camTradeData);
    actions[0] =
      _createFullSignedAction(camAcc, 0, address(tradeModule), camTrade, block.timestamp + 1 days, cam, cam, camPk);

    ITradeModule.TradeData memory dougTradeData = _getDefaultTrade(dougAcc, false);
    bytes memory dougTrade = abi.encode(dougTradeData);
    actions[1] =
      _createFullSignedAction(dougAcc, 0, address(tradeModule), dougTrade, block.timestamp + 1 days, doug, doug, dougPk);
    return actions;
  }

  function _getDefaultTrade(uint recipient, bool isBid) internal view returns (ITradeModule.TradeData memory) {
    return ITradeModule.TradeData({
      asset: address(option),
      subId: defaultCallId,
      limitPrice: 78e18,
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

    ITradeModule.OrderData memory orderData = ITradeModule.OrderData({
      takerAccount: takerAccount,
      takerFee: takerFee,
      fillDetails: fills,
      managerData: bytes("")
    });

    bytes memory encodedAction = abi.encode(orderData);
    return encodedAction;
  }

  function _createMatchedTrades(uint takerAccount, uint takerFee, ITradeModule.FillDetails[] memory makerFills)
    internal
    pure
    returns (bytes memory)
  {
    ITradeModule.OrderData memory orderData = ITradeModule.OrderData({
      takerAccount: takerAccount,
      takerFee: takerFee,
      fillDetails: makerFills,
      managerData: bytes("")
    });

    bytes memory encodedAction = abi.encode(orderData);
    return encodedAction;
  }
}
