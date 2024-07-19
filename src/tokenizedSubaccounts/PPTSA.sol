// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
import {Black76} from "lyra-utils/math/Black76.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "lyra-utils/decimals/SignedDecimalMath.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import {BaseTSA} from "./BaseOnChainSigningTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IOptionAsset} from "v2-core/src/interfaces/IOptionAsset.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IDepositModule} from "../interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IRfqModule} from "../interfaces/IRfqModule.sol";

import {
  StandardManager, IStandardManager, IVolFeed, IForwardFeed
} from "v2-core/src/risk-managers/StandardManager.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";
import {CollateralManagementTSA} from "./CollateralManagementTSA.sol";

/// @title PrincipalProtectedTSA
contract PrincipalProtectedTSA is CollateralManagementTSA {
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
    bool isCallSpread;
    bool isLongSpread;
  }

  struct PPTSAParams {
    /// @dev The maximum amount of gain accepted for opening an option position (e.g. 0.01e18)
    uint maxMarkValueToStrikeDiffRatio;
    /// @dev The minimum amount of gain accepted for opening an option position (e.g. 0.1e18)
    uint minMarkValueToStrikeDiffRatio;
    /// @dev requirement of distance between two strikes
    uint strikeDiff;
    /// @dev the max tolerance we allow when calculating cost of a trade
    uint maxTotalCostTolerance;
    /// @dev used as tolerance for how much TVL we could possibly lose from one RFQ
    uint maxLossOrGainPercentOfTVL;
    /// @dev the max tolerance we allow when calculating cost of a trade
    uint negMaxCashTolerance;
    /// @dev Minimum time before an action is expired
    uint minSignatureExpiry;
    /// @dev Maximum time before an action is expired
    uint maxSignatureExpiry;
    /// @dev Lower bound for option expiry
    uint optionMinTimeToExpiry;
    /// @dev Upper bound for option expiry
    uint optionMaxTimeToExpiry;
    /// @dev Maximum amount of negative cash allowed to be held to open any more option positions. (e.g. -100e18)
    int maxNegCash;
    /// @dev Percentage of an rfq price that can be taken as a fee.
    uint rfqFeeFactor;
  }

  /// @custom:storage-location erc7201:lyra.storage.PrincipalProtectedTSA
  struct PPTSAStorage {
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IRfqModule rfqModule;
    IOptionAsset optionAsset;
    ISpotFeed baseFeed;
    PPTSAParams ppParams;
    CollateralManagementParams collateralManagementParams;
    bool isCallSpread;
    bool isLongSpread;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    bytes32 lastSeenHash;
  }

  struct StrikeData {
    uint strike;
    uint expiry;
    int markPrice;
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

    $.depositModule = ppInitParams.depositModule;
    $.withdrawalModule = ppInitParams.withdrawalModule;
    $.rfqModule = ppInitParams.rfqModule;
    $.tradeModule = ppInitParams.tradeModule;
    $.optionAsset = ppInitParams.optionAsset;
    $.baseFeed = ppInitParams.baseFeed;
    $.isCallSpread = ppInitParams.isCallSpread;
    $.isLongSpread = ppInitParams.isLongSpread;
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setPPTSAParams(CollateralManagementParams memory newCollateralMgmtParams, PPTSAParams memory pptsaParams)
    external
    onlyOwner
  {
    PPTSAStorage storage $ = _getPPTSAStorage();
    if (
      pptsaParams.minSignatureExpiry < 1 minutes || pptsaParams.minSignatureExpiry > pptsaParams.maxSignatureExpiry
        || newCollateralMgmtParams.worstSpotBuyPrice < 1e18 || newCollateralMgmtParams.worstSpotBuyPrice > 1.2e18
        || newCollateralMgmtParams.worstSpotSellPrice > 1e18 || newCollateralMgmtParams.worstSpotSellPrice < 0.8e18
        || newCollateralMgmtParams.spotTransactionLeniency < 1e18
        || newCollateralMgmtParams.spotTransactionLeniency > 1.2e18
        || pptsaParams.minMarkValueToStrikeDiffRatio > pptsaParams.maxMarkValueToStrikeDiffRatio
        || pptsaParams.maxMarkValueToStrikeDiffRatio > 1e18 || pptsaParams.maxMarkValueToStrikeDiffRatio < 1e16
        || pptsaParams.optionMaxTimeToExpiry <= pptsaParams.optionMinTimeToExpiry
        || newCollateralMgmtParams.feeFactor > 0.05e18 || pptsaParams.maxTotalCostTolerance < 2e17
        || pptsaParams.maxTotalCostTolerance > 5e18 || pptsaParams.maxLossOrGainPercentOfTVL < 1e14
        || pptsaParams.maxNegCash > 0 || pptsaParams.rfqFeeFactor > 0.1e18 || pptsaParams.maxLossOrGainPercentOfTVL > 1e18
        || pptsaParams.negMaxCashTolerance < 1e16 || pptsaParams.negMaxCashTolerance > 1e18
        || ($.isLongSpread && pptsaParams.maxTotalCostTolerance < 1e18)
        || (!$.isLongSpread && pptsaParams.maxTotalCostTolerance > 1e18)
    ) {
      revert PPT_InvalidParams();
    }
    _getPPTSAStorage().ppParams = pptsaParams;
    _getPPTSAStorage().collateralManagementParams = newCollateralMgmtParams;

    emit PPTSAParamsSet(pptsaParams, newCollateralMgmtParams);
  }

  function _getCollateralManagementParams() internal view override returns (CollateralManagementParams storage $) {
    return _getPPTSAStorage().collateralManagementParams;
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
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

  /////////////////
  // Withdrawals //
  /////////////////

  function _verifyWithdrawAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    if (withdrawalData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert PPT_InvalidAsset();
    }

    (uint openSpreads, uint baseBalance, int cashBalance) = _getSubAccountStats();

    if (openSpreads != 0) {
      revert PPT_WithdrawingWithOpenTrades();
    }

    uint withdrawalAs18Decimals =
      ConvertDecimals.to18Decimals(withdrawalData.assetAmount, tsaAddresses.depositAsset.decimals());
    if (withdrawalAs18Decimals > baseBalance) {
      revert PPT_InvalidBaseBalance();
    }

    if (cashBalance >= 0) {
      return;
    }

    uint remainingBaseBalance = baseBalance - withdrawalAs18Decimals;
    /*
    * If we have negative cash, we want to make sure we have enough of our base asset to cover our negative cash and then some.
    * This check looks at how much balance we would have left after the withdrawal,
    * and converts it to the cash asset currency.
    *
    * Then we take some number (negMaxCashTolerance) between 1 and .01,
    * and multiply the possible new base balance by that number.
    * negMaxCashTolerance is a safety net if we have a volatile base asset that could quickly drop in respect to cash.
    *
    * If we are below the negative cash balance, we assume we would not be able to cover our negative cash, so we revert.
    *
    * For example: we have -100 cash (assume USDC), and we have 10 base asset. A user wants to withdraw 2 base asset.
    * We would have 8 base asset left over. Assuming 1 base asset is 50 USDC now, we would have 400 USDC left over.
    * Then we multiply 400 by negMaxCashTolerance (let's say .1), so we would need to have 40 USDC left over.
    * This is less than the 100 USDC debt we have, so we would revert.
    */
    if (
      cashBalance.abs()
        > remainingBaseBalance.multiplyDecimal(_getBasePrice()).multiplyDecimal(
          _getPPTSAStorage().ppParams.negMaxCashTolerance
        )
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
      _tradeCollateral(tradeData);
    } else {
      revert PPT_InvalidAsset();
    }
  }

  /// @dev if extraData is 0 this means that the action is a maker action, otherwise it is a taker action
  /// this logic is so the vault can execute as taker and maker while keeping the code aware of all trades
  function _verifyRfqAction(IMatching.Action memory action, bytes memory extraData) internal view {
    uint maxFee;
    IRfqModule.TradeData[] memory makerTrades;
    // non 0 length means the executor is a taker.
    // Since taker does not have an array of the trades, we require the executor to pass in the trades as extraData.
    // If the extraData is 0, we know the executor is a maker so the trades are included in the action.data
    if (extraData.length == 0) {
      IRfqModule.RfqOrder memory makerOrder = abi.decode(action.data, (IRfqModule.RfqOrder));
      maxFee = makerOrder.maxFee;
      makerTrades = makerOrder.trades;
    } else {
      IRfqModule.TakerOrder memory takerOrder = abi.decode(action.data, (IRfqModule.TakerOrder));
      if (keccak256(extraData) != takerOrder.orderHash) {
        revert PPT_TradeDataDoesNotMatchOrderHash();
      }
      maxFee = takerOrder.maxFee;
      makerTrades = abi.decode(extraData, (IRfqModule.TradeData[]));
    }

    (StrikeData memory lowerStrike, StrikeData memory higherStrike) = _validateAndSortStrikes(makerTrades);
    _verifyHigherStrikeAmount(higherStrike.tradeAmount, extraData.length != 0);

    _verifyRfqExecute(lowerStrike, higherStrike, maxFee);
  }

  /// @dev the following function validates whether the maker is selling or buying a spread
  /// The following table determines whether or not the high strike should be sold or bought
  ///
  /// isCallSpread | isLongSpread | isTaker | makerShouldBeSellingSpread
  ///      0       |       0      |    0    |   0 (higherStrike should be < 0)
  ///      0       |       0      |    1    |   1 (higherStrike should be > 0)
  ///      0       |       1      |    0    |   1
  ///      0       |       1      |    1    |   0
  ///      1       |       0      |    0    |   1
  ///      1       |       0      |    1    |   0
  ///      1       |       1      |    0    |   0
  ///      1       |       1      |    1    |   1
  function _verifyHigherStrikeAmount(int strikeAmount, bool isTaker) internal pure {
    PPTSAStorage memory $ = _getPPTSAStorage();
    bool makerShouldBeSellingSpread = ($.isCallSpread == $.isLongSpread) ? isTaker : !isTaker;
    if (makerShouldBeSellingSpread && strikeAmount <= 0) {
      revert PPT_InvalidHighStrikeAmount();
    } else if (!makerShouldBeSellingSpread && strikeAmount >= 0) {
      revert PPT_InvalidHighStrikeAmount();
    }
  }

  function _validateAndSortStrikes(IRfqModule.TradeData[] memory makerTrades)
    internal
    view
    returns (StrikeData memory lowerStrike, StrikeData memory higherStrike)
  {
    if (makerTrades.length != 2) {
      revert PPT_InvalidParams();
    }
    StrikeData memory strike1 = _validateAndCreateIndividualStrike(makerTrades[0]);
    StrikeData memory strike2 = _validateAndCreateIndividualStrike(makerTrades[1]);

    if (
      makerTrades[0].asset != makerTrades[1].asset || makerTrades[0].asset != address(_getPPTSAStorage().optionAsset)
        || strike1.expiry != strike2.expiry
    ) {
      revert PPT_InvalidParams();
    }

    if (strike1.strike > strike2.strike) {
      return (strike2, strike1);
    }
    return (strike1, strike2);
  }

  function _validateAndCreateIndividualStrike(IRfqModule.TradeData memory trade)
    internal
    view
    returns (StrikeData memory)
  {
    PPTSAStorage storage $ = _getPPTSAStorage();
    (uint optionExpiry, uint optionStrike, bool isCall) = OptionEncoding.fromSubId(trade.subId.toUint96());

    if (
      optionExpiry < block.timestamp + $.ppParams.optionMinTimeToExpiry
        || optionExpiry > block.timestamp + $.ppParams.optionMaxTimeToExpiry
    ) {
      revert PPT_OptionExpiryOutOfBounds();
    }

    (uint callPrice, uint putPrice,) = _getOptionPrice(optionExpiry, optionStrike);
    uint markPrice = isCall ? callPrice : putPrice;
    if ($.isCallSpread != isCall) {
      revert PPT_WrongInputSpread();
    }
    return StrikeData({
      strike: optionStrike,
      expiry: optionExpiry,
      markPrice: markPrice.toInt256(),
      tradePrice: trade.price,
      tradeAmount: trade.amount
    });
  }

  function _verifyRfqExecute(StrikeData memory lowerStrike, StrikeData memory higherStrike, uint maxFee) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();
    uint strikeDiff = higherStrike.strike - lowerStrike.strike;
    if (strikeDiff != _getPPTSAStorage().ppParams.strikeDiff) {
      revert PPT_StrikePriceOutsideOfDiff();
    }

    // we always require the trade to be one sell and one buy of equal size, although prices can be different.
    if (higherStrike.tradeAmount != -lowerStrike.tradeAmount) {
      revert PPT_InvalidTradeAmount();
    }

    (uint openSpreads, uint baseBalance, int cashBalance) = _getSubAccountStats();

    if (cashBalance < $.ppParams.maxNegCash) {
      revert PPT_CannotTradeWithTooMuchNegativeCash();
    }

    _verifyRFQFee(maxFee, _getBasePrice());
    _validateTradeDetails(lowerStrike, higherStrike);

    uint maxLossOfOpenOptions = openSpreads.multiplyDecimal(strikeDiff);
    uint totalTradeMaxLossOrGain = higherStrike.tradeAmount.abs().multiplyDecimal(strikeDiff);
    uint baseBalanceAtSpotPrice = baseBalance.multiplyDecimal(_getBasePrice());

    /*
    * The following check is to ensure that if we were to execute this trade,
    * it would not be too large in respect to our TVL.
    *
    * Max loss of open options is the maximum loss the taker would have if all spreads expire worthless.
    * totalTradeMaxLossOrGain is the maximum loss the taker could have if we were to execute this trade.
    * Both of these numbers are in respect to the cashBalance, so they are represented in our cash asset (ex: USDC)
    * We then take our current balance of our base asset, and convert it into a cash number.
    * After multiplying it by a percentage (maxLossOrGainPercentOfTVL),
    * we ensure this trade isn't too large in respect to our TVL.
    */
    if (
      maxLossOfOpenOptions + totalTradeMaxLossOrGain
        > baseBalanceAtSpotPrice.multiplyDecimal($.ppParams.maxLossOrGainPercentOfTVL)
    ) {
      revert PPT_TradeTooLarge();
    }
  }

  function _verifyRFQFee(uint worstTradeFee, uint totalLegAmount) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();
    uint maxAllowedTradeFee = totalLegAmount.multiplyDecimal($.ppParams.rfqFeeFactor).multiplyDecimal(_getBasePrice());
    if (worstTradeFee > maxAllowedTradeFee) {
      revert PPT_TradeFeeTooHigh();
    }
  }

  /////////////////
  // Option Math //
  /////////////////

  function _validateTradeDetails(StrikeData memory lowerStrike, StrikeData memory higherStrike) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();
    int markCostOfTrade = lowerStrike.markPrice.multiplyDecimal(lowerStrike.tradeAmount)
      + higherStrike.markPrice.multiplyDecimal(higherStrike.tradeAmount);

    int actualCostOfTrade = lowerStrike.tradePrice.toInt256().multiplyDecimal(lowerStrike.tradeAmount)
      + higherStrike.tradePrice.toInt256().multiplyDecimal(higherStrike.tradeAmount);

    /*
     * We want to ensure that if we are trading spreads, the cost we're trading isn't too far off from the mark cost.
     * For long spreads, we don't want to pay too much over the mark cost,
     * so maxTotalCostTolerance is a number over 1 (1e18),
     * and if our projected cost is over that tolerance we revert since the trade is too expensive to be reasonable.
     *
     * For short spreads, its the reverse. We don't want to receive too little money for the spread.
     * The same logic applies, but the maxTotalCostTolerance is a number under 1 (1e18).
     * if our projected cost is under that tolerance we revert since the trade is too cheap to be reasonable.
     */
    if (
      $.isLongSpread
        && actualCostOfTrade.abs() > markCostOfTrade.abs().multiplyDecimal($.ppParams.maxTotalCostTolerance)
    ) {
      revert PPT_TotalCostOverTolerance();
    } else if (
      !$.isLongSpread
        && actualCostOfTrade.abs() < markCostOfTrade.abs().multiplyDecimal($.ppParams.maxTotalCostTolerance)
    ) {
      revert PPT_TotalCostBelowTolerance();
    }

    uint markValueToStrikeDiffRatio =
      (lowerStrike.markPrice - higherStrike.markPrice).abs().divideDecimal(higherStrike.strike - lowerStrike.strike);

    /*
     * This check ensures that the (markPrice difference) / (strike Difference) ratio is within a certain range.
     * Typically, the range will be between ~.4 and ~.6, but this can be adjusted in the params.
     * If the ratio is too high then we are buying a spread that is too expensive in respect to the strikes.
     * If too low, the trade is not as risky. This is to force the vault to only make realistic slightly-risky trades.
     */
    if (
      markValueToStrikeDiffRatio < $.ppParams.minMarkValueToStrikeDiffRatio
        || markValueToStrikeDiffRatio > $.ppParams.maxMarkValueToStrikeDiffRatio
    ) {
      revert PPT_MarkValueNotWithinBounds();
    }
  }

  function _getOptionPrice(uint optionExpiry, uint optionStrike)
    internal
    view
    returns (uint callPrice, uint putPrice, uint callDelta)
  {
    uint timeToExpiry = optionExpiry - block.timestamp;
    (uint vol, uint forwardPrice) = _getFeedValues(optionStrike.toUint128(), optionExpiry.toUint64());

    return Black76.pricesAndDelta(
      Black76.Black76Inputs({
        timeToExpirySec: timeToExpiry.toUint64(),
        volatility: vol.toUint128(),
        fwdPrice: forwardPrice.toUint128(),
        strikePrice: optionStrike.toUint128(),
        discount: 1e18
      })
    );
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

  function _getSubAccountStats() internal view returns (uint openSpreads, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();
    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getPPTSAStorage().optionAsset && balances[i].balance > 0) {
        // since we validate that we have a 1:1 ratio between buying and selling between two different strikes,
        // we can just add the positive balances.
        // We just validate that spreads are either open or how much they can lose,
        // so we only care about one side of the balances.
        openSpreads += balances[i].balance.toUint256();
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    return (openSpreads, baseBalance, cashBalance);
  }

  function _getBasePrice() internal view override returns (uint spotPrice) {
    (spotPrice,) = _getPPTSAStorage().baseFeed.getSpot();
  }

  ///////////
  // Views //
  ///////////
  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }

  function getSubAccountStats() public view returns (uint openSpreads, uint baseBalance, int cashBalance) {
    return _getSubAccountStats();
  }

  function getBasePrice() public view returns (uint) {
    return _getBasePrice();
  }

  function getCollateralManagementParams() public view returns (CollateralManagementParams memory) {
    return _getCollateralManagementParams();
  }

  function getPPTSAParams() public view returns (PPTSAParams memory) {
    return _getPPTSAStorage().ppParams;
  }

  function lastSeenHash() public view returns (bytes32) {
    return _getPPTSAStorage().lastSeenHash;
  }

  function getPPTSAAddresses()
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
  event PPTSAParamsSet(PPTSAParams params, CollateralManagementParams collateralManagementParams);

  error PPT_InvalidParams();
  error PPT_InvalidActionExpiry();
  error PPT_InvalidModule();
  error PPT_InvalidAsset();
  error PPT_WithdrawingUtilisedCollateral();
  error PPT_CannotTradeWithTooMuchNegativeCash();
  error PPT_TradeTooLarge();
  error PPT_WrongInputSpread();
  error PPT_InvalidBaseBalance();
  error PPT_InvalidDesiredAmount();
  error PPT_MarkValueNotWithinBounds();
  error PPT_TotalCostOverTolerance();
  error PPT_TotalCostBelowTolerance();
  error PPT_StrikePriceOutsideOfDiff();
  error PPT_InvalidTradeAmount();
  error PPT_TradeDataDoesNotMatchOrderHash();
  error PPT_WithdrawingWithOpenTrades();
  error PPT_InvalidHighStrikeAmount();
  error PPT_OptionExpiryOutOfBounds();
  error PPT_TradeFeeTooHigh();
}
