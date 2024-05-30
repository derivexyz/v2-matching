// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ITradeModule} from "../../src/interfaces/ITradeModule.sol";
import {IActionVerifier} from "../../src/interfaces/IActionVerifier.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";
import "./TSATestUtils.sol";

contract LRTCCTSATest is TSATestUtils {
  LRTCCTSA public tsa;

  uint internal signerPk;
  address internal signer;
  uint internal signerNonce = 0;

  function setUp() public override {
    super.setUp();

    deployPredeposit(address(markets["weth"].base));
    upgradeToLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));

    tsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000e18,
        depositExpiry: 1 weeks,
        minDepositValue: 1e18,
        withdrawalDelay: 1 weeks,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );

    tsa.setLRTCCTSAParams(
      LRTCCTSA.LRTCCTSAParams({
        minSignatureExpiry: 5 minutes,
        maxSignatureExpiry: 30 minutes,
        worstSpotBuyPrice: 1.01e18,
        worstSpotSellPrice: 0.99e18,
        spotTransactionLeniency: 1.01e18,
        optionVolSlippageFactor: 0.9e18,
        optionMaxDelta: 0.15e18,
        optionMinTimeToExpiry: 1 days,
        optionMaxTimeToExpiry: 30 days,
        optionMaxNegCash: -100e18,
        feeFactor: 0.01e18
      })
    );

    tsa.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

  }

  function testCanDepositTradeWithdraw() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(tsa), 10e18);
    uint depositId = tsa.initiateDeposit(1e18, address(this));
    tsa.processDeposit(depositId);

    // shares equal to spot price of 1 weth
    assertEq(tsa.balanceOf(address(this)), 1e18);

    // Register a session key
    tsa.setSigner(signer, true);

    _executeDeposit(0.8e18);

    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0.2e18);
    assertEq(subAccounts.getBalance(tsa.subAccount(), markets["weth"].base, 0), 0.8e18);

    depositId = tsa.initiateDeposit(1e18, address(this));
    tsa.processDeposit(depositId);

    assertEq(tsa.balanceOf(address(this)), 2e18);

    // Withdraw with no PnL

    tsa.requestWithdrawal(0.25e18);

    assertEq(tsa.balanceOf(address(this)), 1.75e18);
    assertEq(tsa.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    tsa.processWithdrawalRequests(1);

    assertEq(tsa.balanceOf(address(this)), 1.75e18);
    assertEq(tsa.totalPendingWithdrawals(), 0);

    assertEq(markets["weth"].erc20.balanceOf(address(this)), 8.25e18); // holding 8 previously

    _executeDeposit(0.5e18);

    uint expiry = block.timestamp + 1 weeks;

    // Open a short perp via trade module
    _tradeOption(-1e18, 200e18, expiry, 2400e18);

    (, int mtmPre) = srm.getMarginAndMarkToMarket(tsa.subAccount(), true, 0);
    _setForwardPrice("weth", uint64(expiry), 2400e18, 1e18);
    (, int mtmPost) = srm.getMarginAndMarkToMarket(tsa.subAccount(), true, 0);

    console2.log("MTM pre: %d", mtmPre);
    console2.log("MTM post: %d", mtmPost);

    // There is now PnL

    tsa.requestWithdrawal(0.25e18);

    assertEq(tsa.balanceOf(address(this)), 1.5e18);
    assertEq(tsa.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    tsa.processWithdrawalRequests(1);

    assertEq(tsa.balanceOf(address(this)), 1.5e18);
    assertEq(tsa.totalPendingWithdrawals(), 0);

    assertApproxEqRel(markets["weth"].erc20.balanceOf(address(this)), 8.43981e18, 0.001e18);
  }

  function _tradeOption(int amount, uint price, uint expiry, uint strike) internal {
    _setForwardPrice("weth", uint64(expiry), 2000e18, 1e18);
    _setDefaultSVIForExpiry("weth", uint64(expiry));

    bytes memory tradeData = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].option),
        subId: OptionEncoding.toSubId(expiry, strike, true),
        limitPrice: int(price),
        desiredAmount: amount,
        worstFee: 1e18,
        recipientId: tsa.subAccount(),
        isBid: amount > 0
      })
    );

    bytes memory tradeMaker = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].option),
        subId: OptionEncoding.toSubId(expiry, strike, true),
        limitPrice: int(price),
        desiredAmount: amount,
        worstFee: 1e18,
        recipientId: takerSubacc,
        isBid: amount < 0
      })
    );

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    actions[0] = IActionVerifier.Action({
      subaccountId: tsa.subAccount(),
      nonce: ++signerNonce,
      module: tradeModule,
      data: tradeData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    (actions[1], signatures[1]) = _createActionAndSign(
      takerSubacc, ++takerNonce, address(tradeModule), tradeMaker, block.timestamp + 1 days, taker, taker, takerPk
    );

    vm.prank(signer);
    tsa.signActionData(actions[0]);

    _verifyAndMatch(
      actions,
      signatures,
      _createMatchedTrade(
        tsa.subAccount(),
        takerSubacc,
        uint(amount > 0 ? amount : -amount),
        int(price),
        // trade fees
        0,
        0
      )
    );
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

  function _executeDeposit(uint amount) internal {
    // Create signed action for cash deposit to empty account
    bytes memory depositData = _encodeDepositData(amount, address(markets["weth"].base), address(0));

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsa.subAccount(),
      nonce: ++signerNonce,
      module: depositModule,
      data: depositData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.prank(signer);
    tsa.signActionData(action);

    _submitToMatching(action);
  }

  function _submitToMatching(IActionVerifier.Action memory action) internal {
    bytes memory encodedAction = abi.encode(action);
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);
    actions[0] = action;
    _verifyAndMatch(actions, signatures, encodedAction);
  }
}
