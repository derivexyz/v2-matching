pragma solidity ^0.8.20;

import "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";
import {MatchingHelpers} from "../shared/MatchingBase.t.sol";
import {TokenizedSubAccount} from "../../src/tokenizedSubaccounts/TSA.sol";
import {
  TransparentUpgradeableProxy,
  ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {LRTCCTSA, BaseTSA, BaseOnChainSigningTSA} from "../../src/tokenizedSubaccounts/LRTCCTSA.sol";

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ITradeModule} from "../../src/interfaces/ITradeModule.sol";
import {IActionVerifier} from "../../src/interfaces/IActionVerifier.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "../../src/interfaces/IMatchingModule.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

contract TSATestUtils is IntegrationTestBase, MatchingHelpers {
  uint internal signerPk;
  address internal signer;
  uint internal signerNonce = 0;

  uint internal takerPk;
  address internal taker;
  uint internal takerNonce = 0;
  uint internal takerSubacc;

  TransparentUpgradeableProxy proxy;
  ProxyAdmin proxyAdmin;

  function setUp() public virtual {
    _setupIntegrationTestComplete();
    _setupMatching();
    _setupTaker();
    _setupMarketFeeds();
    _setupTradeModule();
  }

  function _setupMatching() internal {
    MatchingHelpers._deployMatching(subAccounts, address(cash), auction, 0);
    cash.setWhitelistManager(address(markets["weth"].pmrm), true);
  }

  function _setupTaker() internal {
    takerPk = 0xDEAD;
    taker = vm.addr(takerPk);
    takerSubacc = subAccounts.createAccount(address(this), markets["weth"].pmrm);
    usdc.mint(address(this), 1_000_000e6);
    usdc.approve(address(cash), 1_000_000e6);
    cash.deposit(takerSubacc, 1_000_000e6);

    markets["weth"].base.setTotalPositionCap(markets["weth"].pmrm, 1_000_000e18);
    markets["weth"].base.setTotalPositionCap(srm, 1_000_000e18);

    markets["weth"].erc20.mint(address(this), 100_000e18);
    markets["weth"].erc20.approve(address(markets["weth"].base), 100_000e18);
    markets["weth"].base.deposit(takerSubacc, 100_000e18);

    subAccounts.setApprovalForAll(address(matching), true);
    matching.depositSubAccountFor(takerSubacc, taker);
  }

  function _setupMarketFeeds() internal {
    markets["weth"].spotFeed.setHeartbeat(100 weeks);
    markets["weth"].forwardFeed.setHeartbeat(100 weeks);
    markets["weth"].volFeed.setHeartbeat(100 weeks);
    markets["weth"].perpFeed.setHeartbeat(100 weeks);
    markets["weth"].ibpFeed.setHeartbeat(100 weeks);
    markets["weth"].iapFeed.setHeartbeat(100 weeks);
    markets["weth"].rateFeed.setHeartbeat(100 weeks);
  }

  function _setupTradeModule() internal {
    tradeModule.setFeeRecipient(bobAcc);
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(markets["weth"].id, 0.8e18, 0.8e18);
    srm.setBaseAssetMarginFactor(markets["wbtc"].id, 0.8e18, 0.8e18);
    tradeModule.setPerpAsset(markets["weth"].perp, true);
  }

  function deployPredeposit(address erc20) internal {
    TokenizedSubAccount tsaImplementation = new TokenizedSubAccount();
    proxyAdmin = new ProxyAdmin();
    proxy = new TransparentUpgradeableProxy(
      address(tsaImplementation),
      address(proxyAdmin),
      abi.encodeWithSelector(tsaImplementation.initialize.selector, "TSA", "TSA", erc20)
    );
  }
}

contract LRTCCTSATestUtils is TSATestUtils {
  using SignedMath for int;

  LRTCCTSA public tsa;
  LRTCCTSA public tsaImplementation;
  uint public tsaSubacc;

  LRTCCTSA.LRTCCTSAParams public defaultLrtccTSAParams = LRTCCTSA.LRTCCTSAParams({
    minSignatureExpiry: 5 minutes,
    maxSignatureExpiry: 30 minutes,
    worstSpotBuyPrice: 1.01e18,
    worstSpotSellPrice: 0.99e18,
    spotTransactionLeniency: 1.01e18,
    optionVolSlippageFactor: 0.5e18,
    optionMaxDelta: 0.4e18,
    optionMinTimeToExpiry: 1 days,
    optionMaxTimeToExpiry: 30 days,
    optionMaxNegCash: -100e18,
    feeFactor: 0.01e18
  });

  function upgradeToLRTCCTSA(string memory market) internal {
    IWrappedERC20Asset wrappedDepositAsset;
    ISpotFeed baseFeed;
    IOptionAsset optionAsset;

    // if market is USDC collateral (for decimal tests)
    if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("usdc"))) {
      wrappedDepositAsset = IWrappedERC20Asset(address(cash));
      baseFeed = stableFeed;
      optionAsset = IOptionAsset(address(0));
    } else {
      wrappedDepositAsset = markets[market].base;
      baseFeed = markets[market].spotFeed;
      optionAsset = markets[market].option;
    }

    tsaImplementation = new LRTCCTSA();

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(tsaImplementation),
      abi.encodeWithSelector(
        tsaImplementation.initialize.selector,
        address(this),
        BaseTSA.BaseTSAInitParams({
          subAccounts: subAccounts,
          auction: auction,
          cash: cash,
          wrappedDepositAsset: wrappedDepositAsset,
          manager: srm,
          matching: matching,
          symbol: "Tokenised DN WETH",
          name: "Tokie DN WETH"
        }),
        LRTCCTSA.LRTCCTSAInitParams({
          baseFeed: baseFeed,
          depositModule: depositModule,
          withdrawalModule: withdrawalModule,
          tradeModule: tradeModule,
          optionAsset: optionAsset
        })
      )
    );

    tsa = LRTCCTSA(address(proxy));
    tsaSubacc = tsa.subAccount();
  }

  function setupLRTCCTSA() internal {
    tsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000e18,
        minDepositValue: 1e18,
        withdrawalDelay: 1 weeks,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );

    tsa.setLRTCCTSAParams(defaultLrtccTSAParams);

    tsa.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

    tsa.setSigner(signer, true);
  }

  function _setFixedSVIDataForExpiry(string memory key, uint64 expiry) internal {
    vm.warp(block.timestamp + 1);

    LyraForwardFeed forwardFeed = markets[key].forwardFeed;
    (uint fwdPrice,) = forwardFeed.getForwardPrice(uint64(expiry));

    LyraVolFeed volFeed = markets[key].volFeed;

    IBaseLyraFeed.FeedData memory feedData = _getFixedVolData(expiry, fwdPrice);

    // sign data
    bytes memory data = _signFeedData(volFeed, keeperPk, feedData);

    volFeed.acceptData(data);
  }

  function _getFixedVolData(uint64 expiry, uint fwdPrice) internal view returns (IBaseLyraFeed.FeedData memory) {
    uint64 SVI_refTau = uint64(Black76.annualise(uint64(expiry - block.timestamp)));
    // vol will be sqrt(1.8)
    int SVI_a = int((1.8e18) * uint(SVI_refTau) / 1e18);
    uint SVI_b = 0;
    int SVI_rho = 0;
    int SVI_m = 0;
    uint SVI_sigma = 0;
    uint SVI_fwd = fwdPrice;
    uint64 confidence = 1e18;

    // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05
    bytes memory volData = abi.encode(expiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTau, confidence);
    return IBaseLyraFeed.FeedData({
      data: volData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }

  function _tradeOption(int amount, uint price, uint expiry, uint strike) internal {
    _setForwardPrice("weth", uint64(expiry), 2000e18, 1e18);
    _setFixedSVIDataForExpiry("weth", uint64(expiry));

    bytes memory tradeData = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].option),
        subId: OptionEncoding.toSubId(expiry, strike, true),
        limitPrice: int(price),
        desiredAmount: int(amount.abs()),
        worstFee: 1e18,
        recipientId: tsaSubacc,
        isBid: amount > 0
      })
    );

    bytes memory tradeMaker = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].option),
        subId: OptionEncoding.toSubId(expiry, strike, true),
        limitPrice: int(price),
        desiredAmount: int(amount.abs()),
        worstFee: 1e18,
        recipientId: takerSubacc,
        isBid: amount < 0
      })
    );

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    actions[0] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
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
        tsaSubacc,
        takerSubacc,
        amount.abs(),
        int(price),
        // trade fees
        0,
        0
      )
    );
  }

  function _tradeSpot(int amount, uint price) internal {
    bytes memory tradeData = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].base),
        subId: 0,
        limitPrice: int(price),
        desiredAmount: int(amount.abs()),
        worstFee: 1e18,
        recipientId: tsaSubacc,
        isBid: amount > 0
      })
    );

    bytes memory tradeMaker = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].base),
        subId: 0,
        limitPrice: int(price),
        desiredAmount: int(amount.abs()),
        worstFee: 1e18,
        recipientId: takerSubacc,
        isBid: amount < 0
      })
    );

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    actions[0] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
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
        tsaSubacc,
        takerSubacc,
        amount.abs(),
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

  function _createDepositAction(uint amount) internal returns (IActionVerifier.Action memory) {
    bytes memory depositData = _encodeDepositData(amount, address(markets["weth"].base), address(0));

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++signerNonce,
      module: depositModule,
      data: depositData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    return action;
  }

  function _executeDeposit(uint amount) internal {
    IActionVerifier.Action memory action = _createDepositAction(amount);
    vm.prank(signer);
    tsa.signActionData(action);

    _submitToMatching(action);
  }

  function _createWithdrawalAction(uint amount) internal returns (IActionVerifier.Action memory) {
    bytes memory withdrawalData = _encodeWithdrawData(amount, address(markets["weth"].base));

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++signerNonce,
      module: withdrawalModule,
      data: withdrawalData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    return action;
  }

  function _executeWithdrawal(uint amount) internal {
    IActionVerifier.Action memory action = _createWithdrawalAction(amount);
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

  function _depositToTSA(uint amount) internal {
    markets["weth"].erc20.mint(address(this), amount);
    markets["weth"].erc20.approve(address(tsa), amount);
    uint depositId = tsa.initiateDeposit(amount, address(this));
    tsa.processDeposit(depositId);
  }

  function _createInsolventAuction() internal returns (uint auctionId) {
    auction.setSMAccount(securityModule.accountId());

    uint newSubacc = subAccounts.createAccount(address(this), srm);
    markets["wbtc"].erc20.mint(address(this), 1e18);
    markets["wbtc"].erc20.approve(address(markets["wbtc"].base), 1e18);
    markets["wbtc"].base.deposit(newSubacc, 1e18);

    cash.withdraw(newSubacc, 10_000e6, address(1234));

    vm.warp(block.timestamp + 1);
    _setSpotPrice("wbtc", 0, 1e18);

    auction.startAuction(newSubacc, 0);

    return newSubacc;
  }

  function _clearAuction(uint auctionId) internal {
    uint newSubacc = subAccounts.createAccount(address(this), srm);
    usdc.mint(address(this), 1e18);
    usdc.approve(address(cash), 1e18);
    cash.deposit(newSubacc, 1e18);

    auction.bid(auctionId, newSubacc, 1e18, 0, 0);

    // mint a crazy amount of cash to clear insolvency...
    usdc.mint(address(cash), 1e18);
    cash.disableWithdrawFee();
  }
}
