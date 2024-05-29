// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ITradeModule} from "../../src/interfaces/ITradeModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";
import "../../src/periphery/LyraAuctionUtils.sol";
import "../shared/MatchingBase.t.sol";
import {IntegrationTestBase} from "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";
import {LRTCCTSA} from "../../src/tokenizedSubaccounts/LRTCCTSA.sol";
import {BaseTSA} from "../../src/tokenizedSubaccounts/BaseTSA.sol";

contract TokenizedSubaccountsTest is IntegrationTestBase, MatchingHelpers {
  LRTCCTSA public tokenizedSubacc;

  uint internal signerPk;
  address internal signer;
  uint internal signerNonce = 0;

  uint internal takerPk;
  address internal taker;
  uint internal takerNonce = 0;
  uint internal takerSubacc;

  function setUp() public {
    _setupIntegrationTestComplete();

    MatchingHelpers._deployMatching(subAccounts, address(cash), auction, 0);

    tokenizedSubacc = new LRTCCTSA(
      BaseTSA.BaseTSAInitParams({
        subAccounts: subAccounts,
        auction: auction,
        cash: cash,
        wrappedDepositAsset: markets["weth"].base,
        manager: srm,
        matching: matching,
        symbol: "Tokenised DN WETH",
        name: "Tokie DN WETH"
      }),
      LRTCCTSA.LRTCCTSAInitParams({
        baseFeed: markets["weth"].spotFeed,
        depositModule: depositModule,
        withdrawalModule: withdrawalModule,
        tradeModule: tradeModule,
        optionAsset: markets["weth"].option
      })
    );

    tokenizedSubacc.setTSAParams(
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

    tokenizedSubacc.setLRTCCTSAParams(
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

    tokenizedSubacc.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

    // setup taker with subaccount loaded with cash
    takerPk = 0xDEAD;
    taker = vm.addr(takerPk);
    takerSubacc = subAccounts.createAccount(address(this), markets["weth"].pmrm);
    usdc.mint(address(this), 1_000_000e6);
    usdc.approve(address(cash), 1_000_000e6);
    cash.deposit(takerSubacc, 1_000_000e6);
    subAccounts.setApprovalForAll(address(matching), true);
    matching.depositSubAccountFor(takerSubacc, taker);

    cash.setWhitelistManager(address(markets["weth"].pmrm), true);

    markets["weth"].spotFeed.setHeartbeat(100 weeks);
    markets["weth"].forwardFeed.setHeartbeat(100 weeks);
    markets["weth"].volFeed.setHeartbeat(100 weeks);
    markets["weth"].perpFeed.setHeartbeat(100 weeks);
    markets["weth"].ibpFeed.setHeartbeat(100 weeks);
    markets["weth"].iapFeed.setHeartbeat(100 weeks);

    tradeModule.setFeeRecipient(bobAcc);
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(1, 0.8e18, 0.8e18);
    tradeModule.setPerpAsset(markets["weth"].perp, true);
  }

  function testCanDepositTradeWithdraw() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(tokenizedSubacc), 10e18);
    uint depositId = tokenizedSubacc.initiateDeposit(1e18, address(this));
    tokenizedSubacc.processDeposit(depositId);

    // shares equal to spot price of 1 weth
    assertEq(tokenizedSubacc.balanceOf(address(this)), 1e18);

    // Register a session key
    tokenizedSubacc.setSigner(signer, true);

    _executeDeposit(0.8e18);

    assertEq(markets["weth"].erc20.balanceOf(address(tokenizedSubacc)), 0.2e18);
    assertEq(subAccounts.getBalance(tokenizedSubacc.subAccount(), markets["weth"].base, 0), 0.8e18);

    depositId = tokenizedSubacc.initiateDeposit(1e18, address(this));
    tokenizedSubacc.processDeposit(depositId);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 2e18);

    // Withdraw with no PnL

    tokenizedSubacc.requestWithdrawal(0.25e18);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 1.75e18);
    assertEq(tokenizedSubacc.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    tokenizedSubacc.processWithdrawalRequests(1);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 1.75e18);
    assertEq(tokenizedSubacc.totalPendingWithdrawals(), 0);

    assertEq(markets["weth"].erc20.balanceOf(address(this)), 8.25e18); // holding 8 previously

    _executeDeposit(0.5e18);

    uint expiry = block.timestamp + 1 weeks;

    // Open a short perp via trade module
    _tradeOption(-1e18, 200e18, expiry, 2400e18);

    (, int mtmPre) = srm.getMarginAndMarkToMarket(tokenizedSubacc.subAccount(), true, 0);
    _setForwardPrice("weth", uint64(expiry), 2400e18, 1e18);
    (, int mtmPost) = srm.getMarginAndMarkToMarket(tokenizedSubacc.subAccount(), true, 0);

    console2.log("MTM pre: %d", mtmPre);
    console2.log("MTM post: %d", mtmPost);

    // There is now PnL

    tokenizedSubacc.requestWithdrawal(0.25e18);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 1.5e18);
    assertEq(tokenizedSubacc.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);

    tokenizedSubacc.processWithdrawalRequests(1);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 1.5e18);
    assertEq(tokenizedSubacc.totalPendingWithdrawals(), 0);

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
        recipientId: tokenizedSubacc.subAccount(),
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
      subaccountId: tokenizedSubacc.subAccount(),
      nonce: ++signerNonce,
      module: tradeModule,
      data: tradeData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tokenizedSubacc),
      signer: address(tokenizedSubacc)
    });

    (actions[1], signatures[1]) = _createActionAndSign(
      takerSubacc, ++takerNonce, address(tradeModule), tradeMaker, block.timestamp + 1 days, taker, taker, takerPk
    );

    vm.prank(signer);
    tokenizedSubacc.signActionData(actions[0]);

    _verifyAndMatch(
      actions,
      signatures,
      _createMatchedTrade(
        tokenizedSubacc.subAccount(),
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
      subaccountId: tokenizedSubacc.subAccount(),
      nonce: ++signerNonce,
      module: depositModule,
      data: depositData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tokenizedSubacc),
      signer: address(tokenizedSubacc)
    });

    vm.prank(signer);
    tokenizedSubacc.signActionData(action);

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
