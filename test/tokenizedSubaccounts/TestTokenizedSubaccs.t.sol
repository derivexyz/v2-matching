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
        wrappedDepositAsset: markets["weth"].base,
        manager: srm,
        matching: matching,
        symbol: "Tokenised DN WETH",
        name: "Tokie DN WETH"
      }),
      markets["weth"].spotFeed
    );

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

    tokenizedSubacc.setParams(
      BaseTSA.Params({
        depositCap: 10000e18,
        minDepositValue: 1e18,
        withdrawalDelay: 10 minutes,
        depositScale: 1e18,
        withdrawScale: 1e18
      })
    );

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
    tokenizedSubacc.deposit(1e18);

    // shares equal to spot price of 1 weth
    assertEq(tokenizedSubacc.balanceOf(address(this)), 1e18);

    // Register a session key
    tokenizedSubacc.addSessionKey(signer, block.timestamp + 1 weeks);

    tokenizedSubacc.approveModule(address(depositModule));

    _signerDeposit(0.8e18);

    assertEq(markets["weth"].erc20.balanceOf(address(tokenizedSubacc)), 0.2e18);
    assertEq(subAccounts.getBalance(tokenizedSubacc.subAccount(), markets["weth"].base, 0), 0.8e18);

    tokenizedSubacc.deposit(1e18);
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

    // Open a short perp via trade module
    _tradePerp(-1e18, 2000e18);

    (, int mtmPre) = srm.getMarginAndMarkToMarket(tokenizedSubacc.subAccount(), true, 0);

    _setPerpPrice("weth", 2100e18, 1e18);

    (, int mtmPost) = srm.getMarginAndMarkToMarket(tokenizedSubacc.subAccount(), true, 0);

    assertEq(mtmPost, mtmPre - 100e18);

    // There is now PnL

    tokenizedSubacc.requestWithdrawal(0.25e18);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 1.5e18);
    assertEq(tokenizedSubacc.totalPendingWithdrawals(), 0.25e18);

    vm.warp(block.timestamp + 10 minutes + 1);


    tokenizedSubacc.processWithdrawalRequests(1);

    assertEq(tokenizedSubacc.balanceOf(address(this)), 1.5e18);
    assertEq(tokenizedSubacc.totalPendingWithdrawals(), 0);

    // Pool lost $100 on 3500 value, so 5.7% decrease in value per share. So get back 0.23575 instead of 0.25
    assertApproxEqRel(markets["weth"].erc20.balanceOf(address(this)), 8.48575e18, 0.001e18);
  }

  function _tradePerp(int amount, uint price) internal {
    address perp = address(markets["weth"].perp);

    bytes memory tradeData = abi.encode(
      ITradeModule.TradeData({
        asset: perp,
        subId: 0,
        limitPrice: int(price),
        desiredAmount: amount,
        worstFee: 1e18,
        recipientId: tokenizedSubacc.subAccount(),
        isBid: amount > 0
      })
    );

    bytes memory tradeMaker = abi.encode(
      ITradeModule.TradeData({
        asset: perp,
        subId: 0,
        limitPrice: int(price),
        desiredAmount: amount,
        worstFee: 1e18,
        recipientId: takerSubacc,
        isBid: amount < 0
      })
    );

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);
    (actions[0], signatures[0]) = _createActionAndSign(
      tokenizedSubacc.subAccount(),
      ++signerNonce,
      address(tradeModule),
      tradeData,
      block.timestamp + 1 days,
      address(tokenizedSubacc),
      signer,
      signerPk
    );
    (actions[1], signatures[1]) = _createActionAndSign(
      takerSubacc, ++takerNonce, address(tradeModule), tradeMaker, block.timestamp + 1 days, taker, taker, takerPk
    );

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

  function _signerDeposit(uint amount) internal {
    // Create signed action for cash deposit to empty account
    bytes memory depositData = _encodeDepositData(amount, address(markets["weth"].base), address(0));

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);

    //     uint accountId,
    //    uint signerNonce,
    //    address module,
    //    bytes memory data,
    //    uint expiry,
    //    address owner,
    //    address signer,
    //    uint pk

    (actions[0], signatures[0]) = _createActionAndSign(
      tokenizedSubacc.subAccount(),
      ++signerNonce,
      address(depositModule),
      depositData,
      block.timestamp + 1 days,
      address(tokenizedSubacc),
      signer,
      signerPk
    );

    _verifyAndMatch(actions, signatures, bytes(""));
  }
}
