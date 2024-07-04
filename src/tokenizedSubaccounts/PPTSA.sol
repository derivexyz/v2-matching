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
import {ITradeModule} from "../interfaces/ITradeModule.sol";

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
    ITradeModule tradeModule;
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
    /// @dev The minimum amount of gain accepted for opening an option position (e.g. 0.01e18)
    uint maxMarkValueToStrikeDiffRatio;
    /// @dev The maximum amount of gain accepted for opening an option position (e.g. 0.1e18)
    uint minMarkValueToStrikeDiffRatio;
    /// @dev Lower bound for option expiry
    uint optionMinTimeToExpiry;
    /// @dev Upper bound for option expiry
    uint optionMaxTimeToExpiry;
    /// @dev Percentage of spot that can be paid as a fee for both spot/options (e.g. 0.01e18)
    uint feeFactor;
    /// @dev requirement of distance between two strikes
    uint strikeDiff;
    /// @dev the max tolerance we allow when calculating cost of a trade
    uint maxTotalCostTolerance;
    /// @dev used as tolerance for how much TVL we can use for RFQ
    uint maxBuyPctOfTVL;
    /// @dev the max tolerance we allow when calculating cost of a trade
    uint negMaxCashTolerance;
  }

  /// @custom:storage-location erc7201:lyra.storage.PrincipalProtectedTSA
  struct PPTSAStorage {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IRfqModule rfqModule;
    IOptionAsset optionAsset;
    PPTSAParams ppParams;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    bytes32 lastSeenHash;
  }

  struct StrikeData {
    uint strike;
    uint expiry;
    uint markPrice;
    uint tradePrice;
    int tradeAmount;
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
        || newParams.minMarkValueToStrikeDiffRatio > newParams.maxMarkValueToStrikeDiffRatio
        || newParams.maxMarkValueToStrikeDiffRatio > 1e20 || newParams.maxMarkValueToStrikeDiffRatio < 1e16
        || newParams.optionMaxTimeToExpiry <= newParams.optionMinTimeToExpiry || newParams.feeFactor > 0.05e18
    ) {
      revert PPT_InvalidParams();
    }

    _getPPTSAStorage().ppParams = newParams;

    emit PPTSAParamsSet(newParams);
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  // TODO: Move the account value checks and the selling/buying collat checks and maybe deposits into an abstract contract.
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory extraData)
    internal
    virtual
    override
  {
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
    } else if (address(action.module) == address($.tradeModule)) {
      _verifyTradeAction(action, tsaAddresses);
    } else if (address(action.module) == address($.rfqModule)) {
      _verifyRfqAction(action, extraData);
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

    (bool hasOptions, uint baseBalance, int cashBalance) = _getSubAccountStats();
    if (hasOptions) {
      revert PPT_WithdrawingWithOpenTrades();
    }

    uint amount18 = ConvertDecimals.to18Decimals(withdrawalData.assetAmount, tsaAddresses.depositAsset.decimals());
    if (amount18 > baseBalance) {
      revert PPT_InvalidOptionBalance();
    }

    if (cashBalance >= 0) {
      return;
    }

    if (
      cashBalance.abs().multiplyDecimal(_getPPTSAStorage().ppParams.negMaxCashTolerance)
        < (baseBalance - amount18).multiplyDecimal(_getBasePrice())
    ) {
      revert PPT_WithdrawingUtilisedCollateral();
    }
  }

  /////////////
  // Trading //
  /////////////

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    if (tradeData.desiredAmount <= 0) {
      revert PPT_InvalidDesiredAmount();
    }

    if (tradeData.asset == address(tsaAddresses.wrappedDepositAsset)) {
      if (tradeData.isBid) {
        // Buying more collateral with excess cash
        _verifyCollateralBuy(tradeData, tsaAddresses);
      } else {
        // Selling collateral to cover cash debt
        _verifyCollateralSell(tradeData, tsaAddresses);
      }
      return;
    } else {
      revert PPT_InvalidAsset();
    }
  }

  /// @dev if extraData is 0 this means that the action is a maker action
  /// otherwise it is a taker action
  /// this logic is so the vault can execute as taker and maker while keeping the code aware of all trades
  function _verifyRfqAction(IMatching.Action memory action, bytes memory extraData) internal view {
    uint maxFee;
    IRfqModule.TradeData[] memory trades;
    if (extraData.length == 0) {
      IRfqModule.RfqOrder memory makeOrder = abi.decode(action.data, (IRfqModule.RfqOrder));
      maxFee = makeOrder.maxFee;
      trades = makeOrder.trades;
    } else {
      IRfqModule.TakerOrder memory takerOrder = abi.decode(action.data, (IRfqModule.TakerOrder));
      if (keccak256(extraData) != takerOrder.orderHash) {
        revert PPT_TradeDataDoesNotMatchOrderHash();
      }
      maxFee = takerOrder.maxFee;
      trades = abi.decode(extraData, (IRfqModule.TradeData[]));
    }
    if (trades[0].asset != address(_getPPTSAStorage().optionAsset)) {
      revert PPT_InvalidAsset();
    }

    (StrikeData memory lowerStrike, StrikeData memory higherStrike) = _createStrikes(trades);

    _verifyRfqExecute(lowerStrike, higherStrike, maxFee);
  }

  function _createStrikes(IRfqModule.TradeData[] memory trades)
    internal
    view
    returns (StrikeData memory lowerStrike, StrikeData memory higherStrike)
  {
    if (trades.length != 2 || trades[0].asset != trades[1].asset) {
      revert PPT_InvalidParams();
    }
    StrikeData memory strike1 = _createStrikeData(trades[0]);
    StrikeData memory strike2 = _createStrikeData(trades[1]);
    if (strike1.strike > strike2.strike) {
      return (strike2, strike1);
    }
    return (strike1, strike2);
  }

  function _createStrikeData(IRfqModule.TradeData memory trade) internal view returns (StrikeData memory) {
    (uint expiry, uint strike, uint callPrice) = _getCallPrice(trade);
    return StrikeData({
      strike: strike,
      expiry: expiry,
      markPrice: callPrice,
      tradePrice: trade.price,
      tradeAmount: trade.amount
    });
  }

  // buying collateral will be through the trade module
  function _verifyCollateralBuy(ITradeModule.TradeData memory tradeData, BaseTSAAddresses memory tsaAddresses)
    internal
    view
  {
    PPTSAStorage storage $ = _getPPTSAStorage();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance <= 0) {
      revert PPT_MustHavePositiveCash();
    }
    uint basePrice = _getBasePrice();

    // We don't worry too much about the fee in the calculations, as we trust the exchange won't cause issues. We make
    // sure max fee doesn't exceed 0.5% of spot though.
    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() > basePrice.multiplyDecimal($.ppParams.worstSpotBuyPrice)) {
      revert PPT_SpotLimitPriceTooHigh();
    }

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal($.ppParams.spotTransactionLeniency);
    if (cost > bufferedBalance) {
      revert PPT_BuyingTooMuchCollateral();
    }
  }

  function _verifyCollateralSell(ITradeModule.TradeData memory tradeData, BaseTSAAddresses memory tsaAddresses)
    internal
    view
  {
    PPTSAStorage storage $ = _getPPTSAStorage();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance >= 0) {
      revert PPT_MustHaveNegativeCash();
    }

    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() < basePrice.multiplyDecimal($.ppParams.worstSpotSellPrice)) {
      revert PPT_SpotLimitPriceTooLow();
    }

    // cost is positive, balance is negative
    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal($.ppParams.spotTransactionLeniency);

    // We make sure we're not selling more $ value of collateral than we have in debt
    if (cost.abs() > bufferedBalance.abs()) {
      revert PPT_SellingTooMuchCollateral();
    }
  }

  function _verifyRfqExecute(StrikeData memory lowerStrike, StrikeData memory higherStrike, uint maxFee) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();
    if (higherStrike.strike - lowerStrike.strike != _getPPTSAStorage().ppParams.strikeDiff) {
      revert PPT_StrikePriceOutsideOfDiff();
    }

    if (higherStrike.tradeAmount != -lowerStrike.tradeAmount) {
      revert PPT_InvalidTradeAmountForMaker();
    }

    (, uint baseBalance,) = _getSubAccountStats();

    _verifyFee(maxFee, _getBasePrice());
    int totalCostOfTrade = lowerStrike.tradePrice.toInt256().multiplyDecimal(lowerStrike.tradeAmount)
      + higherStrike.tradePrice.toInt256().multiplyDecimal(higherStrike.tradeAmount);
    _validateOptionDetails(lowerStrike, higherStrike, totalCostOfTrade);

    if (totalCostOfTrade.abs() >= baseBalance.multiplyDecimal($.ppParams.maxBuyPctOfTVL)) {
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

  function _validateOptionDetails(StrikeData memory lowerStrike, StrikeData memory higherStrike, int totalTradeCost)
    internal
    view
  {
    PPTSAStorage storage $ = _getPPTSAStorage();
    int markCost = lowerStrike.markPrice.toInt256().multiplyDecimal(lowerStrike.tradeAmount)
      + higherStrike.markPrice.toInt256().multiplyDecimal(higherStrike.tradeAmount);
    if (markCost > 0) {
      revert PPT_InvalidMarkCost();
    }

    if (totalTradeCost.abs() > markCost.abs().multiplyDecimal($.ppParams.maxTotalCostTolerance)) {
      revert PPT_TotalCostOverTolerance();
    }

    uint markValueToStrikeDiffRatio =
      ((lowerStrike.markPrice - higherStrike.markPrice).divideDecimal(higherStrike.strike - lowerStrike.strike));

    if (
      markValueToStrikeDiffRatio < $.ppParams.minMarkValueToStrikeDiffRatio
        || markValueToStrikeDiffRatio > $.ppParams.maxMarkValueToStrikeDiffRatio
    ) {
      revert PPT_MarkValueNotWithinBounds();
    }
  }

  function _getCallPrice(IRfqModule.TradeData memory trade)
    internal
    view
    returns (uint expiry, uint strike, uint callPrice)
  {
    PPTSAStorage storage $ = _getPPTSAStorage();
    (uint optionExpiry, uint optionStrike, bool isCall) = OptionEncoding.fromSubId(trade.subId.toUint96());
    if (!isCall) {
      revert PPT_OnlyShortCallsAllowed();
    }
    if (block.timestamp >= optionExpiry) {
      revert PPT_OptionExpired();
    }
    uint timeToExpiry = optionExpiry - block.timestamp;
    if (timeToExpiry < $.ppParams.optionMinTimeToExpiry || timeToExpiry > $.ppParams.optionMaxTimeToExpiry) {
      revert PPT_OptionExpiryOutOfBounds();
    }

    (uint vol, uint forwardPrice) = _getFeedValues(optionStrike.toUint128(), optionExpiry.toUint64());

    (callPrice,,) = Black76.pricesAndDelta(
      Black76.Black76Inputs({
        timeToExpirySec: timeToExpiry.toUint64(),
        volatility: vol.toUint128(),
        fwdPrice: forwardPrice.toUint128(),
        strikePrice: optionStrike.toUint128(),
        discount: 1e18
      })
    );
    return (optionExpiry, optionStrike, callPrice);
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

  function _getSubAccountStats() internal view returns (bool hasOptions, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();
    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    hasOptions = false;
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getPPTSAStorage().optionAsset) {
        hasOptions = true;
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    return (hasOptions, baseBalance, cashBalance);
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

  function getSubAccountStats() public view returns (bool hasTradesOpen, uint baseBalance, int cashBalance) {
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
  error PPT_SellingTooManyCalls();
  error PPT_FeeTooHigh();
  error PPT_OnlyShortCallsAllowed();
  error PPT_OptionExpired();
  error PPT_OptionExpiryOutOfBounds();
  error PPT_PositionInsolvent();
  error PPT_InvalidOptionBalance();
  error PPT_InvalidDesiredAmount();
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
  error PPT_TradeDataDoesNotMatchOrderHash();
  error PPT_WithdrawingWithOpenTrades();
}
