// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {FixedPointMathLib} from "lyra-utils/math/FixedPointMathLib.sol";
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
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IDepositModule} from "../interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IRfqModule} from "../interfaces/IRfqModule.sol";

import {
  StandardManager, IStandardManager, IVolFeed, IForwardFeed
} from "v2-core/src/risk-managers/StandardManager.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";
import {CollateralManagementTSA} from "./CollateralManagementTSA.sol";

/// @title LeveragedBasisTSA
/// @notice A TSA that accepts a base asset, borrows against it to buy more, and then opens short perps to neutralise
/// the delta of the borrowed portion, earning the perp funding in the process.
///
/// decision to borrow is based on current perp funding rate and usdc borrow rate. Only borrow more if the perp funding
/// is higher than the borrow rate by a larger degree.
///
/// only closes the position if the borrow rate is higher than the perp funding rate.
contract LeveragedBasisTSA is CollateralManagementTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct LBTSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IPerpAsset perpAsset;
  }

  struct LBTSAParams {
    ///////
    // Guardrail params
    ///////
    // Fees
    uint maxPerpFee;

    // Delta
    int deltaTarget;
    int deltaTargetTolerance;

    // Leverage
    uint leverageFloor;
    uint leverageCeil;

    // EMA
    /// @dev Factor for half life of EMA decay (e.g. 0.0002 ~= 1hr)
    uint emaDecayFactor;
    uint markLossEmaTarget;
  }

  /// @custom:storage-location erc7201:lyra.storage.LeveragedBasisTSA
  struct LBTSAStorage {
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IRfqModule rfqModule;
    IPerpAsset perpAsset;
    ISpotFeed baseFeed;
    LBTSAParams lbParams;
    CollateralManagementParams collateralManagementParams;
    int markLossEma;
    uint markLossLastTs;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    bytes32 lastSeenHash;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.LeveragedBasisTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant LevBasisStorageLocation = 0x880abe6be62a76aa5b3195ed89577651391b09ba97c809a88c84430932fde200;

  function _getLBTSAStorage() private pure returns (LBTSAStorage storage $) {
    assembly {
      $.slot := LevBasisStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    BaseTSA.BaseTSAInitParams memory initParams,
    LBTSAInitParams memory lbInitParams
  ) external reinitializer(1) {
    __BaseTSA_init(initialOwner, initParams);

    LBTSAStorage storage $ = _getLBTSAStorage();

    $.depositModule = lbInitParams.depositModule;
    $.withdrawalModule = lbInitParams.withdrawalModule;
    $.tradeModule = lbInitParams.tradeModule;
    $.baseFeed = lbInitParams.baseFeed;
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setLBTSAParams(LBTSAParams memory lbtsaParams) external onlyOwner {
    LBTSAStorage storage $ = _getLBTSAStorage();

    $.lbParams = lbtsaParams;

    emit LBTSAParamsSet(lbtsaParams);
  }

  function setCollateralManagementParams(CollateralManagementParams memory newCollateralMgmtParams)
    external
    override
    onlyOwner
  {
    if (
      newCollateralMgmtParams.worstSpotBuyPrice < 1e18 || newCollateralMgmtParams.worstSpotBuyPrice > 1.2e18
        || newCollateralMgmtParams.worstSpotSellPrice > 1e18 || newCollateralMgmtParams.worstSpotSellPrice < 0.8e18
        || newCollateralMgmtParams.spotTransactionLeniency < 1e18
        || newCollateralMgmtParams.spotTransactionLeniency > 1.2e18 || newCollateralMgmtParams.feeFactor > 0.05e18
    ) {
      revert("InvalidParams");
    }
    _getLBTSAStorage().collateralManagementParams = newCollateralMgmtParams;

    emit CMTSAParamsSet(newCollateralMgmtParams);
  }

  function _getCollateralManagementParams() internal view override returns (CollateralManagementParams storage $) {
    return _getLBTSAStorage().collateralManagementParams;
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory extraData)
    internal
    virtual
    override
    checkBlocked
  {
    LBTSAStorage storage $ = _getLBTSAStorage();
    // TODO: expiry
    //    if (
    //      action.expiry < block.timestamp + $.lbParams.minSignatureExpiry
    //        || action.expiry > block.timestamp + $.lbParams.maxSignatureExpiry
    //    ) {
    //      revert("PPT_InvalidActionExpiry()");
    //    }

    _revokeSignature($.lastSeenHash);
    $.lastSeenHash = actionHash;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.manager.settlePerpsWithIndex(subAccount());

    if (address(action.module) == address($.depositModule)) {
      _verifyDepositAction(action, tsaAddresses);
    } else if (address(action.module) == address($.withdrawalModule)) {
      _verifyWithdrawAction(action, tsaAddresses);
    } else if (address(action.module) == address($.tradeModule)) {
      _verifyTradeAction(action, tsaAddresses);
    } else {
      revert("InvalidModule");
    }
  }

  /////////////
  // Trading //
  /////////////
  struct TradeHelperVars {
    bool isBaseTrade;
    uint basePrice;
    uint perpPrice;
    int perpPosition;
    uint baseBalance;
    int cashBalance;
    uint underlyingBase;
    int deltaChange;
  }

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal {
    LBTSAStorage memory $ = _getLBTSAStorage();

    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    // either base or perp
    TradeHelperVars memory tradeHelperVars;
    tradeHelperVars.isBaseTrade = tradeData.asset == address(tsaAddresses.depositAsset);

    if (tradeHelperVars.isBaseTrade || tradeData.asset != address($.perpAsset)) {
      revert("InvalidAsset");
    }

    tradeHelperVars.basePrice = _getBasePrice();
    tradeHelperVars.perpPrice = _getPerpPrice();
    (tradeHelperVars.perpPosition, tradeHelperVars.baseBalance, tradeHelperVars.cashBalance) = _getSubAccountStats();
    tradeHelperVars.underlyingBase = _getConvertedMtM();

    // Fees
    if (tradeHelperVars.isBaseTrade) {
      _verifyCollateralTradeFee(tradeData.worstFee, tradeHelperVars.basePrice);
    } else {
      _verifyPerpTradeFee(tradeData.worstFee, tradeHelperVars.perpPrice);
    }

    _verifyTradeDelta(tradeData, tradeHelperVars);
    _verifyTradeLeverage(tradeData.desiredAmount, tradeHelperVars);
    _verifyEmaMarkLoss(tradeData, tradeHelperVars);
  }


  function _verifyWithdrawAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IWithdrawalModule.WithdrawalData memory withdrawData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    // either base or perp
    TradeHelperVars memory tradeHelperVars;
    tradeHelperVars.isBaseTrade = tradeData.asset == address(tsaAddresses.depositAsset);

    if (tradeHelperVars.isBaseTrade || tradeData.asset != address($.perpAsset)) {
      revert("InvalidAsset");
    }

    tradeHelperVars.basePrice = _getBasePrice();
    tradeHelperVars.perpPrice = _getPerpPrice();
    (tradeHelperVars.perpPosition, tradeHelperVars.baseBalance, tradeHelperVars.cashBalance) = _getSubAccountStats();
    tradeHelperVars.underlyingBase = _getConvertedMtM();


    _verifyTradeLeverage(-int(withdrawData.assetAmount), tradeHelperVars);
  }

  /////////////////////////
  // Action Verification //
  /////////////////////////

  function _verifyTradeDelta(
    ITradeModule.TradeData memory tradeData,
    TradeHelperVars memory tradeHelperVars
  ) internal view {
    LBTSAStorage storage $ = _getLBTSAStorage();

    uint perpBaseRatio = tradeHelperVars.perpPrice * 1e18 / tradeHelperVars.basePrice;

    int deltaChange;
    if (tradeData.isBid) {
      deltaChange = tradeHelperVars.isBaseTrade ? tradeData.desiredAmount : tradeData.desiredAmount.multiplyDecimal(int(perpBaseRatio));
    } else {
      deltaChange = tradeHelperVars.isBaseTrade ? -tradeData.desiredAmount: -tradeData.desiredAmount.multiplyDecimal(int(perpBaseRatio));
    }

    // delta as a % of TVL
    int portfolioDeltaPercent = (
      int(tradeHelperVars.baseBalance) + tradeHelperVars.perpPosition.multiplyDecimal(int(perpBaseRatio))
    ).divideDecimal(int(tradeHelperVars.underlyingBase));
    int newDeltaPercent = portfolioDeltaPercent + deltaChange.divideDecimal(int(tradeHelperVars.underlyingBase));
    int targetDelta = $.lbParams.deltaTarget;

    if ((newDeltaPercent - targetDelta).abs() < (portfolioDeltaPercent - targetDelta).abs()) {
      // delta is improving
      return;
    }

    require(
      newDeltaPercent >= targetDelta - $.lbParams.deltaTargetTolerance
      && newDeltaPercent <= targetDelta + $.lbParams.deltaTargetTolerance,
      "PostTradeDeltaOutOfRange"
    );
  }

  function _verifyTradeLeverage(
    int amountBaseChange,
    TradeHelperVars memory tradeHelperVars
  ) internal view {
    if (!tradeHelperVars.isBaseTrade) {
      return;
    }
    LBTSAStorage storage $ = _getLBTSAStorage();

    // Leverage
    uint leverage = tradeHelperVars.baseBalance.divideDecimal(tradeHelperVars.underlyingBase);
    uint newBaseBalance = uint(int(tradeHelperVars.baseBalance) + amountBaseChange);

    uint newLeverage = newBaseBalance.divideDecimal(tradeHelperVars.underlyingBase);

    if (
      (leverage < $.lbParams.leverageFloor && newLeverage > leverage)
      || (leverage > $.lbParams.leverageCeil && newLeverage < leverage)
    ) {
      // leverage is improving
      return;
    }

    require(
      leverage >= $.lbParams.leverageFloor
      && leverage <= $.lbParams.leverageCeil,
      "PostTradeLeverageOutOfRange"
    );
  }

  function _verifyEmaMarkLoss(
    ITradeModule.TradeData memory tradeData,
    TradeHelperVars memory tradeHelperVars
  ) internal {
    LBTSAStorage storage $ = _getLBTSAStorage();

    int priceToCheck = int(tradeHelperVars.isBaseTrade ? tradeHelperVars.basePrice : tradeHelperVars.perpPrice);

    // TODO: fee
    int lossPerUnitCash = tradeData.isBid ? tradeData.limitPrice - priceToCheck : priceToCheck - tradeData.limitPrice;
    int lossPerUnitBase = lossPerUnitCash * 1e18 / int(tradeHelperVars.basePrice);
    // Require that at most we lose X% of the trade value per unit. TODO: param (diff for base/perp)
    require(lossPerUnitBase < 0.02e18, "InvalidGainPerUnit");

    // total loss from trade in base / total tvl in base
    int markLossPercent = tradeData.desiredAmount * lossPerUnitBase / int(tradeHelperVars.underlyingBase);

    int preMarkLossEma = $.markLossEma;

    // convert mark loss -> % of TVL
    int emaLoss = _updateMarkLossEMA(markLossPercent);

    require(
      emaLoss <= int($.lbParams.markLossEmaTarget)
      || emaLoss <= preMarkLossEma,
      "MarkLossTooHigh"
    );
  }

  function _updateMarkLossEMA(int markLossPercent) internal returns (int _markLossEma) {
    LBTSAStorage storage $ = _getLBTSAStorage();

    uint dt = block.timestamp - $.markLossLastTs;
    uint decay = FixedPointMathLib.exp(-int($.lbParams.emaDecayFactor * dt) / 1e18);
    $.markLossEma = $.markLossEma.multiplyDecimal(int(decay)) + markLossPercent;
    $.markLossLastTs = block.timestamp;

    return $.markLossEma;
  }


  function _verifyPerpTradeFee(uint worstFee, uint perpPrice) internal {
    LBTSAStorage storage $ = _getLBTSAStorage();

    require(worstFee.divideDecimal(perpPrice) <= $.lbParams.maxPerpFee, "PerpFeeTooHigh");
  }


  ///////////////////
  // Account Value //
  ///////////////////

  // NOTE: this ignores perp UPnL, so perps should be settled before calling this
  function _getSubAccountStats() internal view returns (int perpPosition, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();
    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    int signedBaseBalance = 0;
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getLBTSAStorage().perpAsset) {
        perpPosition = balances[i].balance;
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        signedBaseBalance = balances[i].balance;
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    if (signedBaseBalance < 0) {
      revert("NegativeBaseBalance");
    }
    if (perpPosition > 0) {
      revert("PositivePerpPosition");
    }

    return (perpPosition, signedBaseBalance.abs(), cashBalance);
  }

  function _getBasePrice() internal view override returns (uint spotPrice) {
    (spotPrice,) = _getLBTSAStorage().baseFeed.getSpot();
  }
//
//  function _getSpotPrice() internal view returns (uint spotPrice) {
//    (spotPrice,) = _getLBTSAStorage().spotFeed.getSpot();
//  }

  function _getPerpPrice() internal view returns (uint perpPrice) {
    (perpPrice,) = _getLBTSAStorage().perpAsset.getPerpPrice();
  }

  ///////////
  // Views //
  ///////////
  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }
//
//  function getSubAccountStats() public view returns (uint openPositiveSpreads, uint baseBalance, int cashBalance) {
//    return _getSubAccountStats();
//  }

  function getBasePrice() public view returns (uint) {
    return _getBasePrice();
  }

  function getCollateralManagementParams() public view returns (CollateralManagementParams memory) {
    return _getCollateralManagementParams();
  }

  function getLBTSAParams() public view returns (LBTSAParams memory) {
    return _getLBTSAStorage().lbParams;
  }

  function lastSeenHash() public view returns (bytes32) {
    return _getLBTSAStorage().lastSeenHash;
  }

  function getLBTSAAddresses()
    public
    view
    returns (ISpotFeed, IDepositModule, IWithdrawalModule, IRfqModule, IPerpAsset)
  {
    LBTSAStorage storage $ = _getLBTSAStorage();
    return ($.baseFeed, $.depositModule, $.withdrawalModule, $.rfqModule, $.perpAsset);
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event LBTSAParamsSet(LBTSAParams lbtsaParams);

}
