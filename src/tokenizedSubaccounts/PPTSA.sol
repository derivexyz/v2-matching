// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
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
import {BaseCollateralManagementTSA} from "./BaseCollateralManagementTSA.sol";

/// @title PrincipalProtectedTSA
contract PrincipalProtectedTSA is BaseCollateralManagementTSA {
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
    BaseCollateralManagementParams baseParams;
    /// @dev The minimum amount of gain accepted for opening an option position (e.g. 0.01e18)
    uint maxMarkValueToStrikeDiffRatio;
    /// @dev The maximum amount of gain accepted for opening an option position (e.g. 0.1e18)
    uint minMarkValueToStrikeDiffRatio;
    /// @dev requirement of distance between two strikes
    uint strikeDiff;
    /// @dev the max tolerance we allow when calculating cost of a trade
    uint maxTotalCostTolerance;
    /// @dev used as tolerance for how much TVL we can use for RFQ
    uint maxBuyPctOfTVL;
    /// @dev the max tolerance we allow when calculating cost of a trade
    uint negMaxCashTolerance;
    /// @dev Minimum time before an action is expired
    uint minSignatureExpiry;
    /// @dev Maximum time before an action is expired
    uint maxSignatureExpiry;
    bool isCallSpread;
    bool isLongSpread;
  }

  /// @custom:storage-location erc7201:lyra.storage.PrincipalProtectedTSA
  struct PPTSAStorage {
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IRfqModule rfqModule;
    BaseCollateralManagementAddresses baseCollateralAddresses;
    PPTSAParams ppParams;
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
    $.baseCollateralAddresses =
      BaseCollateralManagementAddresses({optionAsset: ppInitParams.optionAsset, baseFeed: ppInitParams.baseFeed});
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
        || (newParams.baseParams.worstSpotBuyPrice < 1e18 || newParams.baseParams.worstSpotBuyPrice > 1.2e18)
        || (newParams.baseParams.worstSpotSellPrice > 1e18 || newParams.baseParams.worstSpotSellPrice < 0.8e18)
        || (newParams.baseParams.spotTransactionLeniency < 1e18 || newParams.baseParams.spotTransactionLeniency > 1.2e18)
        || newParams.minMarkValueToStrikeDiffRatio > newParams.maxMarkValueToStrikeDiffRatio
        || newParams.maxMarkValueToStrikeDiffRatio > 1e18 || newParams.maxMarkValueToStrikeDiffRatio < 1e16
        || newParams.strikeDiff > 2e21 || newParams.strikeDiff < 1e20
        || newParams.baseParams.optionMaxTimeToExpiry <= newParams.baseParams.optionMinTimeToExpiry
        || newParams.baseParams.feeFactor > 0.05e18 || newParams.maxTotalCostTolerance < 2e17
        || newParams.maxTotalCostTolerance > 5e18 || newParams.maxBuyPctOfTVL < 1e14 || newParams.maxBuyPctOfTVL > 1e18
        || newParams.negMaxCashTolerance < 1e16 || newParams.negMaxCashTolerance > 1e18
    ) {
      revert PPT_InvalidParams();
    }
    _getPPTSAStorage().ppParams = newParams;

    emit PPTSAParamsSet(newParams);
  }

  function _getBaseCollateralManagementParams()
    internal
    view
    override
    returns (BaseCollateralManagementParams storage $)
  {
    return _getPPTSAStorage().ppParams.baseParams;
  }

  function _getBaseCollateralManagementAddresses()
    internal
    view
    override
    returns (BaseCollateralManagementAddresses memory $)
  {
    return _getPPTSAStorage().baseCollateralAddresses;
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

    (, uint baseBalance, int cashBalance) = _getSubAccountStats();

    uint amount18 = ConvertDecimals.to18Decimals(withdrawalData.assetAmount, tsaAddresses.depositAsset.decimals());
    if (amount18 > baseBalance) {
      revert PPT_InvalidBaseBalance();
    }

    if (cashBalance >= 0) {
      return;
    }

    if (
      cashBalance.abs()
        > (baseBalance - amount18).multiplyDecimal(_getBasePrice()).multiplyDecimal(
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

  /// @dev if extraData is 0 this means that the action is a maker action
  /// otherwise it is a taker action
  /// this logic is so the vault can execute as taker and maker while keeping the code aware of all trades
  function _verifyRfqAction(IMatching.Action memory action, bytes memory extraData) internal view {
    uint maxFee;
    IRfqModule.TradeData[] memory makerTrades;
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
    if (makerTrades[0].asset != address(_getPPTSAStorage().baseCollateralAddresses.optionAsset)) {
      revert PPT_InvalidAsset();
    }

    (StrikeData memory lowerStrike, StrikeData memory higherStrike) = _createStrikes(makerTrades);
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
  function _verifyHigherStrikeAmount(int strikeAmount, bool isTaker) internal view {
    PPTSAParams memory params = _getPPTSAStorage().ppParams;
    bool makerShouldBeSellingSpread = (params.isCallSpread == params.isLongSpread) ? isTaker : !isTaker;
    if (makerShouldBeSellingSpread && strikeAmount <= 0) {
      revert PPT_InvalidStrikeAsTaker();
    } else if (!makerShouldBeSellingSpread && strikeAmount >= 0) {
      revert PPT_InvalidStrikeAsMaker();
    }
  }

  function _createStrikes(IRfqModule.TradeData[] memory makerTrades)
    internal
    view
    returns (StrikeData memory lowerStrike, StrikeData memory higherStrike)
  {
    // TODO: Add check that expiries are the same at that the expiries in here are above min expiry and below max expiry
    if (makerTrades.length != 2 || makerTrades[0].asset != makerTrades[1].asset) {
      revert PPT_InvalidParams();
    }
    StrikeData memory strike1 = _createStrikeData(makerTrades[0]);
    StrikeData memory strike2 = _createStrikeData(makerTrades[1]);
    if (strike1.strike > strike2.strike) {
      return (strike2, strike1);
    }
    return (strike1, strike2);
  }

  function _createStrikeData(IRfqModule.TradeData memory trade) internal view returns (StrikeData memory) {
    (uint expiry, uint strike, uint markPrice) = _getMarkPrice(trade);
    return StrikeData({
      strike: strike,
      expiry: expiry,
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

    if (higherStrike.tradeAmount != -lowerStrike.tradeAmount) {
      revert PPT_InvalidTradeAmount();
    }

    (uint openSpreads, uint baseBalance,) = _getSubAccountStats();

    _verifyFee(maxFee, _getBasePrice());
    _validateTradeDetails(lowerStrike, higherStrike);

    uint maxLossOfOpenOptions = openSpreads.multiplyDecimal(strikeDiff);
    uint totalTradeMaxLoss = higherStrike.tradeAmount.abs().multiplyDecimal(strikeDiff);

    if (
      maxLossOfOpenOptions + totalTradeMaxLoss
        > baseBalance.multiplyDecimal(_getBasePrice()).multiplyDecimal($.ppParams.maxBuyPctOfTVL)
    ) {
      revert PPT_TradeTooLarge();
    }
  }

  /////////////////
  // Option Math //
  /////////////////

  function _validateTradeDetails(StrikeData memory lowerStrike, StrikeData memory higherStrike) internal view {
    PPTSAStorage storage $ = _getPPTSAStorage();
    int markCost = lowerStrike.markPrice.multiplyDecimal(lowerStrike.tradeAmount)
      + higherStrike.markPrice.multiplyDecimal(higherStrike.tradeAmount);

    int totalCostOfTrade = lowerStrike.tradePrice.toInt256().multiplyDecimal(lowerStrike.tradeAmount)
      + higherStrike.tradePrice.toInt256().multiplyDecimal(higherStrike.tradeAmount);

    if ($.ppParams.isLongSpread) {
      if ($.ppParams.maxTotalCostTolerance < 1e18) {
        revert PPT_InvalidCostTolerance();
      } else if (totalCostOfTrade.abs() > markCost.abs().multiplyDecimal($.ppParams.maxTotalCostTolerance)) {
        revert PPT_TotalCostOverTolerance();
      }
    } else {
        if ($.ppParams.maxTotalCostTolerance > 1e18) {
            revert PPT_InvalidCostTolerance();
        } else if (totalCostOfTrade.abs() < markCost.abs().multiplyDecimal($.ppParams.maxTotalCostTolerance)) {
            revert PPT_TotalCostBelowTolerance();
        }
    }

    uint markValueToStrikeDiffRatio =
      ((lowerStrike.markPrice - higherStrike.markPrice).abs().divideDecimal(higherStrike.strike - lowerStrike.strike));

    if (
      markValueToStrikeDiffRatio < $.ppParams.minMarkValueToStrikeDiffRatio
        || markValueToStrikeDiffRatio > $.ppParams.maxMarkValueToStrikeDiffRatio
    ) {
      revert PPT_MarkValueNotWithinBounds();
    }
  }

  function _getMarkPrice(IRfqModule.TradeData memory trade)
    internal
    view
    returns (uint expiry, uint strike, uint markPrice)
  {
    PPTSAStorage storage $ = _getPPTSAStorage();
    (uint optionExpiry, uint optionStrike, bool isCall) = OptionEncoding.fromSubId(trade.subId.toUint96());
    if ($.ppParams.isCallSpread != isCall) {
      revert PPT_WrongInputSpread();
    }
    if (block.timestamp >= optionExpiry) {
      revert PPT_OptionExpired();
    }
    (uint callPrice, uint putPrice,) = _getOptionPrice(optionExpiry, optionStrike);
    markPrice = isCall ? callPrice : putPrice;
    return (optionExpiry, optionStrike, markPrice);
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getSubAccountStats() internal view returns (uint openSpreads, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();
    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getPPTSAStorage().baseCollateralAddresses.optionAsset) {
        openSpreads = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    return (openSpreads, baseBalance, cashBalance);
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
    return (
      $.baseCollateralAddresses.baseFeed,
      $.depositModule,
      $.withdrawalModule,
      $.rfqModule,
      $.baseCollateralAddresses.optionAsset
    );
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
  error PPT_TradeTooLarge();
  error PPT_WrongInputSpread();
  error PPT_OptionExpired();
  error PPT_InvalidBaseBalance();
  error PPT_InvalidDesiredAmount();
  error PPT_MarkValueNotWithinBounds();
  error PPT_TotalCostOverTolerance();
  error PPT_TotalCostBelowTolerance();
  error PPT_InvalidMarkCost();
  error PPT_StrikePriceOutsideOfDiff();
  error PPT_InvalidTradeAmount();
  error PPT_TradeDataDoesNotMatchOrderHash();
  error PPT_WithdrawingWithOpenTrades();
  error PPT_InvalidStrikeAsTaker();
  error PPT_InvalidStrikeAsMaker();
  error PPT_InvalidCostTolerance();
}
