// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {TradeModule, ITradeModule} from "src/modules/TradeModule.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {MockDataReceiver} from "../mock/MockDataReceiver.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import "forge-std/console2.sol";
import "../../src/interfaces/IRfqModule.sol";

contract RfqModuleTest is MatchingBase {
  // Test Rfq
  // - Can fill an order successfully
  // - Can fill multiple orders successfully
  // - perps are filled correctly
  // - Duplicate assets can be filled
  // - Cash can be filled, allowing transfers between accounts with fees
  // - charges fees as expected
  // - can submit feed data
  // - Reverts in different cases
  //  - mismatch of subaccounts provided and in action
  //  - hashed order mismatch

  function testFillSpotRfqOrder() public {
    weth.mint(address(this), 10e18);
    weth.approve(address(baseAsset), 10e18);
    baseAsset.deposit(dougAcc, 10e18);

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](1);
    trades[0] = IRfqModule.TradeData({asset: address(baseAsset), subId: 0, markPrice: 1500e18, amount: 10e18});
    _submitRfqTrade(trades);

    assertEq(subAccounts.getBalance(camAcc, baseAsset, 0), 10e18);
    assertEq(subAccounts.getBalance(dougAcc, baseAsset, 0), 0);

    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) - 15000e18);
  }

  function testFillOptionBox() public {
    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](4);
    trades[0] = IRfqModule.TradeData({
      asset: address(option),
      subId: OptionEncoding.toSubId(block.timestamp + 1 weeks, 1500e18, true),
      markPrice: 300e18,
      amount: 2e18
    });
    trades[1] = IRfqModule.TradeData({
      asset: address(option),
      subId: OptionEncoding.toSubId(block.timestamp + 1 weeks, 1500e18, false),
      markPrice: -300e18,
      amount: -2e18
    });
    trades[2] = IRfqModule.TradeData({
      asset: address(option),
      subId: OptionEncoding.toSubId(block.timestamp + 1 weeks, 1700e18, true),
      markPrice: 200e18,
      amount: -2e18
    });
    trades[3] = IRfqModule.TradeData({
      asset: address(option),
      subId: OptionEncoding.toSubId(block.timestamp + 1 weeks, 1700e18, false),
      markPrice: -400e18,
      amount: 2e18
    });
    _submitRfqTrade(trades);
  }

  function testFillPerpRfqOrder() public {
    mockPerp.setMockPerpPrice(1500e18, 1e18);

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](1);
    trades[0] = IRfqModule.TradeData({asset: address(mockPerp), subId: 0, markPrice: 1490e18, amount: 10e18});
    _submitRfqTrade(trades);

    assertEq(subAccounts.getBalance(camAcc, mockPerp, 0), 10e18);
    assertEq(subAccounts.getBalance(dougAcc, mockPerp, 0), -10e18);

    // cam receives 10 per perp, as the mark price is 10 under the perp price
    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) + 100e18);
  }

  function testFillSameAssetMultipleTimes() public {
    weth.mint(address(this), 10e18);
    weth.approve(address(baseAsset), 10e18);
    baseAsset.deposit(dougAcc, 10e18);

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](3);
    trades[0] = IRfqModule.TradeData({asset: address(baseAsset), subId: 0, markPrice: 1490e18, amount: 2e18});
    trades[1] = IRfqModule.TradeData({asset: address(baseAsset), subId: 0, markPrice: 1490e18, amount: 3e18});
    trades[2] = IRfqModule.TradeData({asset: address(baseAsset), subId: 0, markPrice: 1490e18, amount: 1e18});
    _submitRfqTrade(trades);

    assertEq(subAccounts.getBalance(camAcc, baseAsset, 0), 6e18);
    assertEq(subAccounts.getBalance(dougAcc, baseAsset, 0), 4e18);

    // cam receives 10 per perp, as the mark price is 10 under the perp price
    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) - 8940e18);
  }

  function testCanFillCash() public {
    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](1);
    // asking for $100 from others
    trades[0] = IRfqModule.TradeData({asset: address(cash), subId: 0, markPrice: 0, amount: 100e18});
    _submitRfqTrade(trades);

    assertEq(subAccounts.getBalance(camAcc, cash, 0), int(cashDeposit) + 100e18);
  }

  function testCanSubmitFeedDataWithTransfer() public {
    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](1);
    // asking for $100 from others
    trades[0] = IRfqModule.TradeData({asset: address(cash), subId: 0, markPrice: 0, amount: 100e18});

    IBaseManager.ManagerData[] memory data = new IBaseManager.ManagerData[](1);
    data[0] = IBaseManager.ManagerData({receiver: bob, data: ""});

    (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) =
      _getRfqTradeData(trades, abi.encode(data));

    // Easiest way to test that the call to the receiver happened, since tests aren't setup to support full feeds
    // This reverts on trying to call an invalid function, so no error code to catch
    vm.expectRevert();
    _verifyAndMatch(actions, signatures, actionData);
  }

  function testChargesFees() public {
    weth.mint(address(this), 10e18);
    weth.approve(address(baseAsset), 10e18);
    baseAsset.deposit(dougAcc, 10e18);

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](1);
    trades[0] = IRfqModule.TradeData({
      asset: address(baseAsset),
      subId: 0,
      // 0 mark price so no funds are sent besides fees
      markPrice: 0,
      amount: 1e18
    });

    IRfqModule.RfqOrder memory rfqOrder = IRfqModule.RfqOrder({maxFee: 0, trades: trades});
    IRfqModule.TakerOrder memory takerOrder =
      IRfqModule.TakerOrder({orderHash: keccak256(abi.encode(rfqOrder)), maxFee: 0});
    IRfqModule.OrderData memory orderData =
      IRfqModule.OrderData({makerAccount: camAcc, makerFee: 0, takerAccount: dougAcc, takerFee: 0, managerData: ""});
    // Reverts if trying to charge a fee when no allowance set
    orderData.makerFee = 1;
    IActionVerifier.Action[] memory actions;
    bytes[] memory signatures;

    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);
    vm.expectRevert(IRfqModule.RFQM_FeeTooHigh.selector);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    orderData.makerFee = 0;
    orderData.takerFee = 1;

    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);
    vm.expectRevert(IRfqModule.RFQM_FeeTooHigh.selector);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    orderData.takerFee = 0;

    // charges only maker fee
    rfqOrder.maxFee = 10e18;
    takerOrder.orderHash = keccak256(abi.encode(rfqOrder));
    orderData.makerFee = 8e18;

    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), 8e18);

    // charges only taker fee
    takerOrder.maxFee = 10e18;
    orderData.makerFee = 0;
    orderData.takerFee = 9e18;

    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 1, 1);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), 17e18);

    // charges both fees
    orderData.makerFee = 6e18;

    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 2, 2);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    // 17 + 6 + 9 = 32
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), 32e18);
  }

  function testRfqRevertScenarios() public {
    weth.mint(address(this), 10e18);
    weth.approve(address(baseAsset), 10e18);
    baseAsset.deposit(dougAcc, 10e18);

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](1);
    trades[0] = IRfqModule.TradeData({
      asset: address(baseAsset),
      subId: 0,
      // 0 mark price so no funds are sent besides fees
      markPrice: 0,
      amount: 1e18
    });

    IRfqModule.RfqOrder memory rfqOrder = IRfqModule.RfqOrder({maxFee: 0, trades: trades});
    IRfqModule.TakerOrder memory takerOrder =
      IRfqModule.TakerOrder({orderHash: keccak256(abi.encode(rfqOrder)), maxFee: 0});
    IRfqModule.OrderData memory orderData =
      IRfqModule.OrderData({makerAccount: camAcc, makerFee: 0, takerAccount: dougAcc, takerFee: 0, managerData: ""});

    IActionVerifier.Action[] memory actions;
    bytes[] memory signatures;

    // mismatch of subaccounts provided and in action
    orderData.takerAccount = camAcc;
    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);
    vm.expectRevert(IRfqModule.RFQM_SignedAccountMismatch.selector);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    orderData.takerAccount = dougAcc;
    orderData.makerAccount = dougAcc;
    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);
    vm.expectRevert(IRfqModule.RFQM_SignedAccountMismatch.selector);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    orderData.makerAccount = camAcc;

    // hashed order mismatch
    rfqOrder.maxFee = 10e18;
    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);
    vm.expectRevert(IRfqModule.RFQM_InvalidTakerHash.selector);
    _verifyAndMatch(actions, signatures, abi.encode(orderData));

    // too many actions
    IActionVerifier.Action[] memory badActions = new IActionVerifier.Action[](3);
    bytes[] memory badSignatures = new bytes[](3);
    badActions[0] = actions[0];
    badActions[1] = actions[1];
    badActions[2] = actions[1];
    badSignatures[0] = signatures[0];
    badSignatures[1] = signatures[1];
    badSignatures[2] = signatures[1];
    vm.expectRevert(IRfqModule.RFQM_InvalidActionsLength.selector);
    _verifyAndMatch(badActions, badSignatures, abi.encode(orderData));

    // not enough actions
    badActions = new IActionVerifier.Action[](1);
    badSignatures = new bytes[](1);
    badActions[0] = actions[0];
    badSignatures[0] = signatures[0];
    vm.expectRevert(IRfqModule.RFQM_InvalidActionsLength.selector);
    _verifyAndMatch(badActions, badSignatures, abi.encode(orderData));
  }

  function _submitRfqTrade(IRfqModule.TradeData[] memory trades) internal {
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) =
      _getRfqTradeData(trades, "");
    _verifyAndMatch(actions, signatures, actionData);
  }

  function _getRfqTradeData(IRfqModule.TradeData[] memory trades, bytes memory managerData)
    internal
    returns (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData)
  {
    IRfqModule.RfqOrder memory rfqOrder = IRfqModule.RfqOrder({maxFee: 0, trades: trades});
    IRfqModule.TakerOrder memory takerOrder =
      IRfqModule.TakerOrder({orderHash: keccak256(abi.encode(rfqOrder)), maxFee: 0});
    IRfqModule.OrderData memory orderData = IRfqModule.OrderData({
      makerAccount: camAcc,
      makerFee: 0,
      takerAccount: dougAcc,
      takerFee: 0,
      managerData: managerData
    });

    (actions, signatures) = _signAndGetActions(rfqOrder, takerOrder, 0, 0);

    return (actions, signatures, abi.encode(orderData));
  }

  function _signAndGetActions(
    IRfqModule.RfqOrder memory rfqOrder,
    IRfqModule.TakerOrder memory takerOrder,
    uint makerNonce,
    uint takerNonce
  ) internal returns (IActionVerifier.Action[] memory actions, bytes[] memory signatures) {
    actions = new IActionVerifier.Action[](2);
    signatures = new bytes[](2);

    (actions[0], signatures[0]) = _createActionAndSign(
      camAcc, makerNonce, address(rfqModule), abi.encode(rfqOrder), block.timestamp + 1 days, cam, cam, camPk
    );

    (actions[1], signatures[1]) = _createActionAndSign(
      dougAcc, takerNonce, address(rfqModule), abi.encode(takerOrder), block.timestamp + 1 days, doug, doug, dougPk
    );

    return (actions, signatures);
  }
}
