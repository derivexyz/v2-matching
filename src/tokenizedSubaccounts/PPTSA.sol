// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
import {Black76} from "lyra-utils/math/Black76.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "lyra-utils/decimals/SignedDecimalMath.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import {BaseOnChainSigningTSA, BaseTSA} from "./BaseOnChainSigningTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IOptionAsset} from "v2-core/src/interfaces/IOptionAsset.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IDepositModule} from "../interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {IMatching} from "../interfaces/IMatching.sol";

import {
  StandardManager, IStandardManager, IVolFeed, IForwardFeed
} from "v2-core/src/risk-managers/StandardManager.sol";
import {IRfqModule} from "../interfaces/IRfqModule.sol";
import "../interfaces/ITradeModule.sol";

/// @title PrincipalProtectedTSA
/// @notice TSA that accepts any deposited collateral, and sells RFQ spreads on any gained principal.
contract PrincipalProtectedTSA is BaseOnChainSigningTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct PPTSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    IRfqModule rfqModule;
    IOptionAsset optionAsset;
  }

  struct PPTSAParams {
    /// @dev Minimum time before an action is expired
    uint minSignatureExpiry;
    /// @dev Maximum time before an action is expired
    uint maxSignatureExpiry;
    /// @dev Percentage of spot price that the TSA will buy baseAsset at in the worst case (e.g. 1.02e18)
    uint worstSpotBuyPrice;
    /// @dev Percentage of spot price that the TSA will sell baseAsset at in the worst case (e.g. 0.98e18)
    uint worstSpotSellPrice;
    /// @dev A factor on how strict to be with preventing too much cash being used in swapping base asset (e.g. 1.01e18)
    int spotTransactionLeniency;
    /// @dev The worst difference to vol that is accepted for pricing options (e.g. 0.9e18)
    uint optionVolSlippageFactor;
    /// @dev The minimum amount of gain accepted for opening an option position (e.g. 0.01e18)
    /// POC: This is new
    uint maxMarkValueToStrikeDiffRatio;
    /// @dev The maximum amount of gain accepted for opening an option position (e.g. 0.1e18)
    /// POC: This is new
    uint minMarkValueToStrikeDiffRatio;
    /// @dev Lower bound for option expiry
    uint optionMinTimeToExpiry;
    /// @dev Upper bound for option expiry
    uint optionMaxTimeToExpiry;
    /// @dev Maximum amount of negative cash allowed to be held to open any more option positions. (e.g. -100e18)
    int optionMaxNegCash;
    /// @dev Percentage of spot that can be paid as a fee for both spot/options (e.g. 0.01e18)
    uint feeFactor;
    /// @dev requirement of distance between two strikes
    /// POC: This is new
    int strikeDiff;
    /// @dev the max tolerance we allow when calculating cost of a trade
    /// POC: This is new
    uint maxTotalCostTolerance;
    /// @dev used as tolerance for how much TVL we can use for RFQ
    /// POC: This is new
    uint maxBuyPctOfTVL;
  }

  /// @custom:storage-location erc7201:lyra.storage.PrincipalProtectedTSA
  struct PPTSAStorage {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    IRfqModule rfqModule;
    IOptionAsset optionAsset;
    PPTSAParams ppParams;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    bytes32 lastSeenHash;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.PrincipalProtectedTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant PPTSAStorageLocation = 0x273fadd8b9727c49bd8eabddca41871e1e7fc468f40ece57b00a1bd25002e500;

  function _getPPTSAStorage() private pure returns (PPTSAStorage storage $) {
    assembly {
      $.slot := PPTSAStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    BaseTSA.BaseTSAInitParams memory initParams,
    PPTSAInitParams memory ppInitParams
  ) external reinitializer(2) {
    __BaseTSA_init(initialOwner, initParams);

    PPTSAStorage storage $ = _getPPTSAStorage();

    $.baseFeed = ppInitParams.baseFeed;

    $.depositModule = ppInitParams.depositModule;
    $.withdrawalModule = ppInitParams.withdrawalModule;
    $.rfqModule = ppInitParams.rfqModule;
    $.optionAsset = ppInitParams.optionAsset;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setPPTSAParams(PPTSAParams memory newParams) external onlyOwner {
    // TODO: Add new params to this check. (What are some good bounds for these normally?)
    if (
      newParams.minSignatureExpiry < 1 minutes || newParams.minSignatureExpiry > newParams.maxSignatureExpiry
        || (newParams.worstSpotBuyPrice < 1e18 || newParams.worstSpotBuyPrice > 1.2e18)
        || (newParams.worstSpotSellPrice > 1e18 || newParams.worstSpotSellPrice < 0.8e18)
        || (newParams.spotTransactionLeniency < 1e18 || newParams.spotTransactionLeniency > 1.2e18)
        || newParams.optionVolSlippageFactor > 1e18
        || newParams.minMarkValueToStrikeDiffRatio < newParams.maxMarkValueToStrikeDiffRatio
        || newParams.maxMarkValueToStrikeDiffRatio > 1e20 || newParams.maxMarkValueToStrikeDiffRatio < 1e18
        || newParams.optionMaxTimeToExpiry <= newParams.optionMinTimeToExpiry || newParams.optionMaxNegCash > 0
        || newParams.feeFactor > 0.05e18
    ) {
      revert PPT_InvalidParams();
    }

    _getPPTSAStorage().ppParams = newParams;

    emit PPTSAParamsSet(newParams);
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash) internal virtual override {
    PPTSAStorage storage $ = _getPPTSAStorage();

    if (
      action.expiry < block.timestamp + $.ppParams.minSignatureExpiry
        || action.expiry > block.timestamp + $.ppParams.maxSignatureExpiry
    ) {
      revert PPT_InvalidActionExpiry();
    }

    _revokeSignature($.lastSeenHash);
    $.lastSeenHash = actionHash;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    if (address(action.module) == address($.depositModule)) {
      _verifyDepositAction(action, tsaAddresses);
    } else if (address(action.module) == address($.withdrawalModule)) {
      _verifyWithdrawAction(action, tsaAddresses);
    } else if (address(action.module) == address($.rfqModule)) {
      _verifyTradeAction(action, tsaAddresses);
    } else {
      revert PPT_InvalidModule();
    }
  }

  //////////////
  // Deposits //
  //////////////

  function _verifyDepositAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IDepositModule.DepositData memory depositData = abi.decode(action.data, (IDepositModule.DepositData));

    if (depositData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert PPT_InvalidAsset();
    }

    if (depositData.amount > tsaAddresses.depositAsset.balanceOf(address(this)) - totalPendingDeposits()) {
      revert PPT_DepositingTooMuch();
    }
  }

  /////////////////
  // Withdrawals //
  /////////////////

  function _verifyWithdrawAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    if (withdrawalData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert PPT_InvalidAsset();
    }

    (int usedInTradesBalance, uint baseBalance, int cashBalance) = _getSubAccountStats();

    uint amount18 = ConvertDecimals.to18Decimals(withdrawalData.assetAmount, tsaAddresses.depositAsset.decimals());
    uint requestedCollateral = amount18 + usedInTradesBalance.min(0).toUint256();
    if (usedInTradesBalance < 0) requestedCollateral = 0;

    if (baseBalance < requestedCollateral) {
      revert PPT_WithdrawingUtilisedCollateral();
    }

    if (cashBalance + usedInTradesBalance < _getPPTSAStorage().ppParams.optionMaxNegCash) {
      revert PPT_WithdrawalNegativeCash();
    }
  }

  /////////////
  // Trading //
  /////////////

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IRfqModule.RfqOrder memory tradeData = abi.decode(action.data, (IRfqModule.RfqOrder));
    if (tradeData.trades.length == 0) {
      revert PPT_InvalidParams();
    }

    if (tradeData.trades[0].asset == address(tsaAddresses.wrappedDepositAsset)) {
      if (tradeData.trades.length != 1) {
        revert PPT_InvalidParams();
      }
      if (tradeData.trades[0].asset != address(tsaAddresses.wrappedDepositAsset)) {
        revert PPT_InvalidAsset();
      }
      if (tradeData.trades[0].amount > 0) {
        _verifyCollateralBuy(tradeData, tsaAddresses);
      } else {
        _verifyCollateralSell(tradeData, tsaAddresses);
      }
      return;
    } else if (tradeData.trades[0].asset == address(_getPPTSAStorage().optionAsset)) {
      _verifyRfqExecute(tradeData);
    } else {
      revert PPT_InvalidAsset();
    }
  }

  function _verifyCollateralBuy(IRfqModule.RfqOrder memory tradeData, BaseTSAAddresses memory tsaAddresses)
    internal
    view
  {
    PPTSAStorage storage $ = _getPPTSAStorage();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance <= 0) {
      revert PPT_MustHavePositiveCash();
    }
    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.maxFee, basePrice);

    if (tradeData.trades[0].price > basePrice.multiplyDecimal($.ppParams.worstSpotBuyPrice)) {
      revert PPT_SpotLimitPriceTooHigh();
    }

    int cost = tradeData.trades[0].price.toInt256().multiplyDecimal(tradeData.trades[0].amount);
    int bufferedBalance = cashBalance.multiplyDecimal($.ppParams.spotTransactionLeniency);
    if (cost > bufferedBalance) {
      revert PPT_BuyingTooMuchCollateral();
    }
  }

  function _verifyCollateralSell(IRfqModule.RfqOrder memory tradeData, BaseTSAAddresses memory tsaAddresses)
    internal
    view
  {
    PPTSAStorage storage $ = _getPPTSAStorage();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance >= 0) {
      revert PPT_MustHaveNegativeCash();
    }

    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.maxFee, basePrice);

    if (tradeData.trades[0].price < basePrice.multiplyDecimal($.ppParams.worstSpotSellPrice)) {
      revert PPT_SpotLimitPriceTooLow();
    }

    // cost is positive, balance is negative
    uint cost = tradeData.trades[0].price.multiplyDecimal(tradeData.trades[0].amount.toUint256());
    int bufferedBalance = cashBalance.multiplyDecimal($.ppParams.spotTransactionLeniency);

    // We make sure we're not selling more $ value of collateral than we have in debt
    if (cost > bufferedBalance.abs()) {
      revert PPT_SellingTooMuchCollateral();
    }
  }

  function _verifyRfqExecute(IRfqModule.RfqOrder memory tradeData) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();
    if (tradeData.trades.length != 2) {
      revert PPT_InvalidParams();
    }
    if (tradeData.trades[0].asset != tradeData.trades[1].asset) {
      revert PPT_InvalidParams();
    }

    (, uint strike1,) = OptionEncoding.fromSubId(tradeData.trades[0].subId.toUint96());
    (, uint strike2,) = OptionEncoding.fromSubId(tradeData.trades[1].subId.toUint96());
    if (strike1 < strike2 || (strike1 - strike2).toInt256() != _getPPTSAStorage().ppParams.strikeDiff) {
      revert PPT_StrikePriceOutsideOfDiff();
    }

    // TODO: if the amount is less than 0 does that indicate a sell?
    if (tradeData.trades[0].amount != -tradeData.trades[1].amount || tradeData.trades[0].amount < 0) {
      revert PPT_InvalidTradeAmountForMaker();
    }
    // trade array is from MM side so MM is selling call spreads.
    // so we should expect the first trade to be a sell on the lower strike price,
    // and the second trade to be a buy on the higher strike price
    if (strike1 >= strike2) {
      revert PPT_InvalidParams();
    }
    // base balance is sUSDe
    (int amountUsedInTrades, uint baseBalance, int cashBalance) = _getSubAccountStats();

    if (cashBalance < _getPPTSAStorage().ppParams.optionMaxNegCash) {
      revert PPT_CannotCommitRFQWithNegativeCash();
    }

    _verifyFee(tradeData.maxFee, _getBasePrice());
    int totalCostOfTrade = _validateOptionDetails(tradeData);
    if (
      (totalCostOfTrade + amountUsedInTrades).min(0).toUint256()
        >= baseBalance.multiplyDecimal($.ppParams.maxBuyPctOfTVL)
    ) {
      revert PPT_SellingTooManyCalls();
    }
  }

  function _verifyFee(uint worstFee, uint basePrice) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();

    if (worstFee > basePrice.multiplyDecimal($.ppParams.feeFactor)) {
      revert PPT_FeeTooHigh();
    }
  }

  /////////////////
  // Option Math //
  /////////////////

  function _validateOptionDetails(IRfqModule.RfqOrder memory tradeData) internal view returns (int totalCost) {
    PPTSAStorage storage $ = _getPPTSAStorage();
    int markCost = 0;
    uint[] memory tradePrices = new uint[](2);

    for (uint i = 0; i < tradeData.trades.length; i++) {
      IRfqModule.TradeData memory trade = tradeData.trades[i];
      uint callPrice = _getCallPrice(trade);
      tradePrices[i] = callPrice;
      totalCost += trade.price.toInt256().multiplyDecimal(trade.amount);

      markCost += callPrice.toInt256().multiplyDecimal(trade.amount);
    }
    if (markCost < 0) {
      // the more expensive option should be the lower strike price since its deeper MTM
      // so mark cost should always be above 0 since MM is selling the deeper ITM option (selling means amount is positive)
      revert PPT_InvalidMarkCost();
    }
    if (totalCost.abs() > markCost.abs().multiplyDecimal($.ppParams.maxTotalCostTolerance)) {
      revert PPT_TotalCostOverTolerance();
    }
    (, uint strike1,) = OptionEncoding.fromSubId(tradeData.trades[0].subId.toUint96());
    (, uint strike2,) = OptionEncoding.fromSubId(tradeData.trades[1].subId.toUint96());
    uint markValueToStrikeDiffRatio = ((strike2 - strike1).divideDecimal((tradePrices[1] - tradePrices[0])));
    if (
      markValueToStrikeDiffRatio < $.ppParams.minMarkValueToStrikeDiffRatio
        || markValueToStrikeDiffRatio > $.ppParams.maxMarkValueToStrikeDiffRatio
    ) {
      revert PPT_MarkValueNotWithinBounds();
    }
    return totalCost;
  }

  function _getCallPrice(IRfqModule.TradeData memory trade) internal view returns (uint callPrice) {
    PPTSAStorage storage $ = _getPPTSAStorage();
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(trade.subId.toUint96());
    if (!isCall) {
      revert PPT_OnlyShortCallsAllowed();
    }
    if (block.timestamp >= expiry) {
      revert PPT_OptionExpired();
    }
    uint timeToExpiry = expiry - block.timestamp;
    if (timeToExpiry < $.ppParams.optionMinTimeToExpiry || timeToExpiry > $.ppParams.optionMaxTimeToExpiry) {
      revert PPT_OptionExpiryOutOfBounds();
    }

    (uint vol, uint forwardPrice) = _getFeedValues(strike.toUint128(), expiry.toUint64());

    (callPrice,,) = Black76.pricesAndDelta(
      Black76.Black76Inputs({
        timeToExpirySec: timeToExpiry.toUint64(),
        volatility: (vol.multiplyDecimal($.ppParams.optionVolSlippageFactor)).toUint128(),
        fwdPrice: forwardPrice.toUint128(),
        strikePrice: strike.toUint128(),
        discount: 1e18
      })
    );
    return callPrice;
  }

  function _getFeedValues(uint128 strike, uint64 expiry) internal view returns (uint vol, uint forwardPrice) {
    PPTSAStorage storage $ = _getPPTSAStorage();

    StandardManager srm = StandardManager(address(getBaseTSAAddresses().manager));
    IStandardManager.AssetDetail memory assetDetails = srm.assetDetails($.optionAsset);
    (, IForwardFeed fwdFeed, IVolFeed volFeed) = srm.getMarketFeeds(assetDetails.marketId);
    (vol,) = volFeed.getVol(strike, expiry);
    (forwardPrice,) = fwdFeed.getForwardPrice(expiry);
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getSubAccountStats() internal view returns (int tradeBalance, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();
    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getPPTSAStorage().optionAsset) {
        // Note: switching this to int since we will have a negative balance from buying ITM options.
        // possibly offsetting slightly by selling slightly higher strike price options.
        // Is this right?
        tradeBalance += balances[i].balance;
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    return (tradeBalance, baseBalance, cashBalance);
  }

  function _getBasePrice() internal view returns (uint) {
    (uint spotPrice,) = _getPPTSAStorage().baseFeed.getSpot();
    return spotPrice;
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getAccountValue(bool includePending) internal view override returns (uint) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    uint depositAssetBalance = tsaAddresses.depositAsset.balanceOf(address(this));
    if (!includePending) {
      depositAssetBalance -= totalPendingDeposits();
    }

    (int margin, int mtm) = tsaAddresses.manager.getMarginAndMarkToMarket(subAccount(), true, 0);
    uint spotPrice = _getBasePrice();

    // convert to depositAsset value but in 18dp
    int convertedMtM = mtm.divideDecimal(spotPrice.toInt256());

    // Now convert to appropriate decimals
    uint8 decimals = tsaAddresses.depositAsset.decimals();
    if (decimals > 18) {
      convertedMtM = convertedMtM.multiplyDecimal(int(10 ** (decimals - 18)));
    } else if (decimals < 18) {
      convertedMtM = convertedMtM / int(10 ** (18 - decimals));
    }

    // Might not be technically insolvent (could have enough depositAsset to cover the deficit), but we block deposits
    // and withdrawals whenever the margin is negative (i.e. liquidatable)
    if (convertedMtM < 0 || margin < 0) {
      revert PPT_PositionInsolvent();
    }

    return uint(convertedMtM) + depositAssetBalance;
  }

  ///////////
  // Views //
  ///////////
  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }

  function getSubAccountStats() public view returns (int numShortCalls, uint baseBalance, int cashBalance) {
    return _getSubAccountStats();
  }

  function getBasePrice() public view returns (uint) {
    return _getBasePrice();
  }

  function getCCTSAParams() public view returns (PPTSAParams memory) {
    return _getPPTSAStorage().ppParams;
  }

  function lastSeenHash() public view returns (bytes32) {
    return _getPPTSAStorage().lastSeenHash;
  }

  function getCCTSAAddresses()
    public
    view
    returns (ISpotFeed, IDepositModule, IWithdrawalModule, IRfqModule, IOptionAsset)
  {
    PPTSAStorage storage $ = _getPPTSAStorage();
    return ($.baseFeed, $.depositModule, $.withdrawalModule, $.rfqModule, $.optionAsset);
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event PPTSAParamsSet(PPTSAParams params);

  error PPT_InvalidParams();
  error PPT_InvalidActionExpiry();
  error PPT_InvalidModule();
  error PPT_InvalidAsset();
  error PPT_DepositingTooMuch();
  error PPT_WithdrawingUtilisedCollateral();
  error PPT_WithdrawalNegativeCash();
  error PPT_SellingTooManyCalls();
  error PPT_CannotCommitRFQWithNegativeCash();
  error PPT_FeeTooHigh();
  error PPT_OnlyShortCallsAllowed();
  error PPT_OptionExpired();
  error PPT_OptionExpiryOutOfBounds();
  error PPT_OptionPriceTooLow();
  error PPT_PositionInsolvent();
  error PPT_InvalidOptionBalance();
  error PPT_InvalidDesiredAmount();
  error PPT_CanOnlyOpenShortOptions();
  error PPT_MustHavePositiveCash();
  error PPT_BuyingTooMuchCollateral();
  error PPT_SpotLimitPriceTooHigh();
  error PPT_MustHaveNegativeCash();
  error PPT_SellingTooMuchCollateral();
  error PPT_SpotLimitPriceTooLow();
  error PPT_MarkValueNotWithinBounds();
  error PPT_TotalCostOverTolerance();
  error PPT_InvalidMarkCost();
  error PPT_StrikePriceOutsideOfDiff();
  error PPT_InvalidTradeAmountForMaker();
}
