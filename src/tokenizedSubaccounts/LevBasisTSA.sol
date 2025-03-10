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
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";

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
    // Trade bounds
    uint maxPerpFee;
    /// @dev Max loss per unit of base traded, in base
    int maxBaseLossPerBase;
    /// @dev Max loss per unit of perp traded, in base
    int maxBaseLossPerPerp;
    // Delta of the portfolio as a % of TVL (0.5 = 50% delta of TVL)
    int deltaFloor;
    int deltaCeil;
    // Leverage
    uint leverageFloor;
    uint leverageCeil;
    // EMA
    /// @dev Factor for half life of EMA decay (e.g. 0.0002 ~= 1hr)
    uint emaDecayFactor;
    /// @dev Target % of tvl that we can maximally lose via EMA calculation
    uint markLossEmaTarget;
    uint minSignatureExpiry;
    uint maxSignatureExpiry;
  }

  /// @custom:storage-location erc7201:lyra.storage.LeveragedBasisTSA
  struct LBTSAStorage {
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IPerpAsset perpAsset;
    ISpotFeed baseFeed;
    LBTSAParams lbParams;
    CollateralManagementParams collateralManagementParams;
    int markLossEma;
    uint markLossLastTs;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    /// Note: off-chain multiple "atomic" actions can be considered valid at once. Only once they are partially filled
    /// would a new order on-chain invalidate the previous one.
    bytes32 lastSeenHash;
  }

  struct TradeHelperVars {
    bool isBaseTrade;
    uint basePrice;
    uint perpPrice;
    int perpPosition;
    /// Actual base balance held within the subaccount.
    uint baseBalance;
    int cashBalance;
    /// This is the MtM of the subaccount, converted to base. Used for leverage caluclations.
    /// BaseBalance == underlyingBase == 1x leverage
    uint underlyingBase;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.LeveragedBasisTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant LEV_BASIS_STORAGE_LOCATION =
    0x880abe6be62a76aa5b3195ed89577651391b09ba97c809a88c84430932fde200;

  function _getLBTSAStorage() internal pure returns (LBTSAStorage storage $) {
    assembly {
      $.slot := LEV_BASIS_STORAGE_LOCATION
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    BaseTSA.BaseTSAInitParams memory initParams,
    LBTSAInitParams memory lbInitParams
  ) external reinitializer(2) {
    __BaseTSA_init(initialOwner, initParams);

    LBTSAStorage storage $ = _getLBTSAStorage();

    $.depositModule = lbInitParams.depositModule;
    $.withdrawalModule = lbInitParams.withdrawalModule;
    $.tradeModule = lbInitParams.tradeModule;
    $.baseFeed = lbInitParams.baseFeed;
    $.perpAsset = lbInitParams.perpAsset;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setLBTSAParams(LBTSAParams memory lbtsaParams) external onlyOwner {
    if (
      // || lbtsaParams.deltaTarget < -0.2e18 || lbtsaParams.deltaTarget > 0.2e18 // ±20%
      // Note: because of atomic singing, these can be very low. Signatures might come in last second.
      lbtsaParams.maxPerpFee > 0.01e18 // Max 1% fee
        || lbtsaParams.deltaFloor > 1e18 || lbtsaParams.deltaCeil < 1e18 // 1 delta is always allowed
        || lbtsaParams.leverageCeil < lbtsaParams.leverageFloor || lbtsaParams.leverageCeil > 5e18 // Must be > floor
        || lbtsaParams.emaDecayFactor == 0 // Must be non-zero
        || lbtsaParams.markLossEmaTarget > 0.2e18 // Max param 20%
        || lbtsaParams.maxBaseLossPerBase < 0 || lbtsaParams.maxBaseLossPerBase > 0.05e18 // 0-5%
        || lbtsaParams.maxBaseLossPerPerp < 0 || lbtsaParams.maxBaseLossPerPerp > 0.05e18 // 0-5%
        || lbtsaParams.minSignatureExpiry > lbtsaParams.maxSignatureExpiry
    ) {
      revert LBT_InvalidParams();
    }

    _getLBTSAStorage().lbParams = lbtsaParams;

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
      revert LBT_InvalidParams();
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
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory /*extraData*/ )
    internal
    virtual
    override
    checkBlocked
  {
    LBTSAStorage storage $ = _getLBTSAStorage();

    if (
      action.expiry < block.timestamp + $.lbParams.minSignatureExpiry
        || action.expiry > block.timestamp + $.lbParams.maxSignatureExpiry
    ) {
      revert LBT_InvalidActionExpiry();
    }

    // if the action hash is the same as the last one, we revoke and then re-enable it afterwards (see _signActionData)
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
      revert LBT_InvalidModule();
    }
  }

  /////////////
  // Trading //
  /////////////

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal {
    LBTSAStorage memory $ = _getLBTSAStorage();

    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    // either base or perp
    TradeHelperVars memory tradeHelperVars =
      _getTradeHelperVars(tradeData.asset, address(tsaAddresses.wrappedDepositAsset), address($.perpAsset));

    // Fees
    if (tradeHelperVars.isBaseTrade) {
      _verifyCollateralTradeFee(tradeData.worstFee, tradeHelperVars.basePrice);
    } else {
      _verifyPerpTradeFee(tradeData.worstFee, tradeHelperVars.perpPrice);
    }

    int amtDelta = tradeData.isBid ? tradeData.desiredAmount : -tradeData.desiredAmount;

    _verifyTradeDelta(tradeHelperVars, amtDelta, false);
    _verifyTradeLeverage(tradeHelperVars, amtDelta, false);
    _verifyEmaMarkLoss(tradeData, tradeHelperVars);
  }

  function _verifyWithdrawAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    LBTSAStorage storage $ = _getLBTSAStorage();
    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    require(withdrawalData.asset == address(tsaAddresses.wrappedDepositAsset), LBT_InvalidWithdrawAsset());

    TradeHelperVars memory tradeHelperVars =
      _getTradeHelperVars(withdrawalData.asset, address(tsaAddresses.wrappedDepositAsset), address($.perpAsset));

    _verifyTradeLeverage(tradeHelperVars, -int(withdrawalData.assetAmount), true);
    _verifyTradeDelta(tradeHelperVars, -int(withdrawalData.assetAmount), true);
  }

  //////////////////////////
  // Verification Helpers //
  //////////////////////////

  function _getTradeHelperVars(address asset, address wrappedDepositAsset, address perpAsset)
    internal
    view
    returns (TradeHelperVars memory tradeHelperVars)
  {
    tradeHelperVars.isBaseTrade = asset == wrappedDepositAsset;

    require(tradeHelperVars.isBaseTrade || asset == perpAsset, LBT_InvalidTradeAsset());

    tradeHelperVars.basePrice = _getBasePrice();
    tradeHelperVars.perpPrice = _getPerpPrice();
    (tradeHelperVars.perpPosition, tradeHelperVars.baseBalance, tradeHelperVars.cashBalance) = _getSubAccountStats();
    tradeHelperVars.underlyingBase = _getConvertedMtM();
  }

  function _verifyTradeDelta(TradeHelperVars memory tradeHelperVars, int amtDelta, bool isWithdrawal) internal view {
    LBTSAStorage storage $ = _getLBTSAStorage();

    uint perpBaseRatio = tradeHelperVars.perpPrice.divideDecimal(tradeHelperVars.basePrice);
    int newUnderlyingBase = int(tradeHelperVars.underlyingBase);

    // early exit if we are withdrawing everything
    if (tradeHelperVars.isBaseTrade && isWithdrawal) {
      // only for base withdrawals will underlyingBase be reduced
      newUnderlyingBase += amtDelta;

      // Note, there could be positive or negative cash, but that is not considered here
      if (newUnderlyingBase == 0 && tradeHelperVars.perpPosition == 0) return;
    }

    // prevent div by 0
    require(newUnderlyingBase > 0, LBT_InvalidDeltaChange());

    int baseExposure =
      int(tradeHelperVars.baseBalance) + tradeHelperVars.perpPosition.multiplyDecimal(int(perpBaseRatio));

    // delta as a % of TVL
    int preDeltaPercent = baseExposure.divideDecimal(tradeHelperVars.underlyingBase.toInt256());

    int deltaChange = tradeHelperVars.isBaseTrade ? amtDelta : amtDelta.multiplyDecimal(int(perpBaseRatio));
    int newDeltaPercent = (baseExposure + deltaChange).divideDecimal(newUnderlyingBase);

    require(
      _isWithinBounds(preDeltaPercent, newDeltaPercent, $.lbParams.deltaFloor, $.lbParams.deltaCeil),
      LBT_PostTradeDeltaOutOfRange()
    );
  }

  function _verifyTradeLeverage(TradeHelperVars memory tradeHelperVars, int amtDelta, bool isWithdrawal) internal view {
    if (!tradeHelperVars.isBaseTrade) {
      return;
    }
    LBTSAStorage storage $ = _getLBTSAStorage();

    uint newUnderlyingBase =
      isWithdrawal ? uint(int(tradeHelperVars.underlyingBase) + amtDelta) : tradeHelperVars.underlyingBase;

    // Leverage
    uint leverage = tradeHelperVars.baseBalance.divideDecimal(tradeHelperVars.underlyingBase);
    uint newBaseBalance = uint(int(tradeHelperVars.baseBalance) + amtDelta);

    // handle zero case
    if (newBaseBalance == 0 && newUnderlyingBase == 0) return;

    uint newLeverage = newBaseBalance.divideDecimal(newUnderlyingBase);

    require(
      _isWithinBounds(int(leverage), int(newLeverage), int($.lbParams.leverageFloor), int($.lbParams.leverageCeil)),
      LBT_PostTradeLeverageOutOfRange()
    );
  }

  function _isWithinBounds(int oldValue, int newValue, int floor, int ceil) internal pure returns (bool) {
    if (newValue >= floor && newValue <= ceil) {
      return true;
    }

    // improving from below floor
    if (oldValue < floor && newValue > oldValue && newValue < ceil) {
      return true;
    }

    // improving from above ceil
    if (oldValue > ceil && newValue < oldValue && newValue > floor) {
      return true;
    }

    return false;
  }

  function _verifyEmaMarkLoss(ITradeModule.TradeData memory tradeData, TradeHelperVars memory tradeHelperVars) internal {
    LBTSAStorage storage $ = _getLBTSAStorage();

    int priceToCheck = int(tradeHelperVars.isBaseTrade ? tradeHelperVars.basePrice : tradeHelperVars.perpPrice);

    // Note, we don't include fee in the loss calculation
    int lossPerUnitCash = tradeData.isBid ? tradeData.limitPrice - priceToCheck : priceToCheck - tradeData.limitPrice;
    int lossPerUnitBase = lossPerUnitCash * 1e18 / int(tradeHelperVars.basePrice);

    // Require that at most we lose X% of the trade value per unit.
    require(
      lossPerUnitBase <= (tradeHelperVars.isBaseTrade ? $.lbParams.maxBaseLossPerBase : $.lbParams.maxBaseLossPerPerp),
      LBT_InvalidGainPerUnit()
    );

    // total loss from trade in base / total tvl in base
    int markLossPercent = tradeData.desiredAmount * lossPerUnitBase / int(tradeHelperVars.underlyingBase);

    int preMarkLossEma = _decayAndFetchEma();
    int emaLoss = preMarkLossEma + markLossPercent;
    $.markLossEma = emaLoss;

    require(emaLoss <= int($.lbParams.markLossEmaTarget) || emaLoss <= preMarkLossEma, LBT_MarkLossTooHigh());
  }

  function _decayAndFetchEma() internal returns (int newEma) {
    LBTSAStorage storage $ = _getLBTSAStorage();

    uint dt = block.timestamp - $.markLossLastTs;
    uint decay = FixedPointMathLib.exp(-int($.lbParams.emaDecayFactor * dt));
    $.markLossEma = $.markLossEma.multiplyDecimal(int(decay));
    $.markLossLastTs = block.timestamp;

    return $.markLossEma;
  }

  function _verifyPerpTradeFee(uint worstFee, uint perpPrice) internal view {
    LBTSAStorage storage $ = _getLBTSAStorage();

    require(worstFee.divideDecimal(perpPrice) <= $.lbParams.maxPerpFee, LBT_PerpFeeTooHigh());
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
    require(signedBaseBalance >= 0, LBT_NegativeBaseBalance());
    require(perpPosition <= 0, LBT_PositivePerpPosition());

    return (perpPosition, signedBaseBalance.abs(), cashBalance);
  }

  function _getBasePrice() internal view override returns (uint spotPrice) {
    (spotPrice,) = _getLBTSAStorage().baseFeed.getSpot();
  }

  function _getPerpPrice() internal view returns (uint perpPrice) {
    (perpPrice,) = _getLBTSAStorage().perpAsset.getPerpPrice();
  }

  ///////////
  // Views //
  ///////////
  function getTradeHelperVars(address asset) external view returns (TradeHelperVars memory tradeHelperVars) {
    tradeHelperVars = _getTradeHelperVars(
      asset, address(getBaseTSAAddresses().wrappedDepositAsset), address(_getLBTSAStorage().perpAsset)
    );
  }

  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }

  function getSubAccountStats() public view returns (int perpPosition, uint baseBalance, int cashBalance) {
    return _getSubAccountStats();
  }

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

  function getLBTSAEmaValues() public view returns (int markLossEma, uint markLossLastTs) {
    return (_getLBTSAStorage().markLossEma, _getLBTSAStorage().markLossLastTs);
  }

  function getLBTSAAddresses()
    public
    view
    returns (ISpotFeed, IDepositModule, IWithdrawalModule, ITradeModule, IPerpAsset)
  {
    LBTSAStorage storage $ = _getLBTSAStorage();
    return ($.baseFeed, $.depositModule, $.withdrawalModule, $.tradeModule, $.perpAsset);
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event LBTSAParamsSet(LBTSAParams lbtsaParams);

  error LBT_InvalidWithdrawalAmount();
  error LBT_InvalidDeltaChange();
  error LBT_InvalidParams();
  error LBT_InvalidActionExpiry();
  error LBT_InvalidModule();
  error LBT_InvalidWithdrawAsset();
  error LBT_InvalidTradeAsset();
  error LBT_PostTradeLeverageOutOfRange();
  error LBT_PostTradeDeltaOutOfRange();
  error LBT_InvalidGainPerUnit();
  error LBT_MarkLossTooHigh();
  error LBT_PerpFeeTooHigh();
  error LBT_NegativeBaseBalance();
  error LBT_PositivePerpPosition();
}
