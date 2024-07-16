// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
import {Black76} from "lyra-utils/math/Black76.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "lyra-utils/decimals/SignedDecimalMath.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import {BaseOnChainSigningTSA} from "./BaseOnChainSigningTSA.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import "v2-core/src/risk-managers/StandardManager.sol";
import "../interfaces/IDepositModule.sol";

abstract contract BaseCollateralManagementTSA is BaseOnChainSigningTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct BaseCollateralManagementAddresses {
    IOptionAsset optionAsset;
    ISpotFeed baseFeed;
  }

  struct BaseCollateralManagementParams {
    /// @dev Percentage of spot that can be paid as a fee for both spot/options (e.g. 0.01e18)
    uint feeFactor;
    /// @dev A factor on how strict to be with preventing too much cash being used in swapping base asset (e.g. 1.01e18)
    int spotTransactionLeniency;
    /// @dev Percentage of spot price that the TSA will sell baseAsset at in the worst case (e.g. 0.98e18)
    uint worstSpotSellPrice;
    /// @dev Percentage of spot price that the TSA will sell baseAsset at in the worst case (e.g. 0.98e18)
    uint worstSpotBuyPrice;
    /// @dev Lower bound for option expiry
    uint optionMinTimeToExpiry;
    /// @dev Upper bound for option expiry
    uint optionMaxTimeToExpiry;
  }

  ///////////////////
  //     Admin     //
  ///////////////////

  function _getBaseCollateralManagementAddresses()
    internal
    view
    virtual
    returns (BaseCollateralManagementAddresses memory $);

  function _getBaseCollateralManagementParams()
    internal
    view
    virtual
    returns (BaseCollateralManagementParams storage $);

  ///////////////////
  // Verification  //
  ///////////////////

  function _tradeCollateral(ITradeModule.TradeData memory tradeData) internal view {
    if (tradeData.isBid) {
      // Buying more collateral with excess cash
      _verifyCollateralBuy(tradeData);
    } else {
      // Selling collateral to cover cash debt
      _verifyCollateralSell(tradeData);
    }
  }

  // buying collateral will be through the trade module
  function _verifyCollateralBuy(ITradeModule.TradeData memory tradeData) internal view {
    BaseCollateralManagementParams storage baseParams = _getBaseCollateralManagementParams();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance <= 0) {
      revert BCMTSA_MustHavePositiveCash();
    }
    uint basePrice = _getBasePrice();

    // We don't worry too much about the fee in the calculations, as we trust the exchange won't cause issues. We make
    // sure max fee doesn't exceed 0.5% of spot though.
    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() > basePrice.multiplyDecimal(baseParams.worstSpotBuyPrice)) {
      revert BCMTSA_SpotLimitPriceTooHigh();
    }

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal(baseParams.spotTransactionLeniency);
    if (cost > bufferedBalance) {
      revert BCMTSA_BuyingTooMuchCollateral();
    }
  }

  function _verifyCollateralSell(ITradeModule.TradeData memory tradeData) internal view {
    BaseCollateralManagementParams storage baseParams = _getBaseCollateralManagementParams();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance >= 0) {
      revert BCMTSA_MustHaveNegativeCash();
    }

    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() < basePrice.multiplyDecimal(baseParams.worstSpotSellPrice)) {
      revert BCMTSA_SpotLimitPriceTooLow();
    }

    // cost is positive, balance is negative
    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal(baseParams.spotTransactionLeniency);

    // We make sure we're not selling more $ value of collateral than we have in debt
    if (cost.abs() > bufferedBalance.abs()) {
      revert BCMTSA_SellingTooMuchCollateral();
    }
  }

  function _verifyFee(uint worstFee, uint basePrice) internal view {
    BaseCollateralManagementParams storage baseParams = _getBaseCollateralManagementParams();

    if (worstFee > basePrice.multiplyDecimal(baseParams.feeFactor)) {
      revert BCMTSA_FeeTooHigh();
    }
  }

  //////////////
  // Deposits //
  //////////////

  // TODO: This looks a little odd. Thew only full action in the base class. Should we create a child function that calls this function?
  function _verifyDepositAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IDepositModule.DepositData memory depositData = abi.decode(action.data, (IDepositModule.DepositData));

    if (depositData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert BCMTSA_InvalidAsset();
    }

    if (depositData.amount > tsaAddresses.depositAsset.balanceOf(address(this)) - totalPendingDeposits()) {
      revert BCMTSA_DepositingTooMuch();
    }
  }

  /////////////////
  // Option Math //
  /////////////////

  function _getOptionPrice(uint optionExpiry, uint optionStrike)
    internal
    view
    returns (uint callPrice, uint putPrice, uint callDelta)
  {
    BaseCollateralManagementParams memory params = _getBaseCollateralManagementParams();
    uint timeToExpiry = optionExpiry - block.timestamp;
    if (timeToExpiry < params.optionMinTimeToExpiry || timeToExpiry > params.optionMaxTimeToExpiry) {
      revert BCMTSA_OptionExpiryOutOfBounds();
    }
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
    BaseCollateralManagementAddresses memory $ = _getBaseCollateralManagementAddresses();

    StandardManager srm = StandardManager(address(getBaseTSAAddresses().manager));
    IStandardManager.AssetDetail memory assetDetails = srm.assetDetails($.optionAsset);
    (, IForwardFeed fwdFeed, IVolFeed volFeed) = srm.getMarketFeeds(assetDetails.marketId);
    (vol,) = volFeed.getVol(strike, expiry);
    (forwardPrice,) = fwdFeed.getForwardPrice(expiry);
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
      convertedMtM = convertedMtM * int(10 ** (decimals - 18));
    } else if (decimals < 18) {
      convertedMtM = convertedMtM / int(10 ** (18 - decimals));
    }

    // Might not be technically insolvent (could have enough depositAsset to cover the deficit), but we block deposits
    // and withdrawals whenever the margin is negative (i.e. liquidatable)
    if (convertedMtM < 0 || margin < 0) {
      revert BCMTSA_PositionInsolvent();
    }

    return uint(convertedMtM) + depositAssetBalance;
  }

  function _getBasePrice() internal view returns (uint spotPrice) {
    (spotPrice,) = _getBaseCollateralManagementAddresses().baseFeed.getSpot();
  }

  error BCMTSA_DepositingTooMuch();
  error BCMTSA_OptionExpiryOutOfBounds();
  error BCMTSA_PositionInsolvent();
  error BCMTSA_InvalidDesiredAmount();
  error BCMTSA_InvalidAsset();
  error BCMTSA_MustHavePositiveCash();
  error BCMTSA_SpotLimitPriceTooHigh();
  error BCMTSA_BuyingTooMuchCollateral();
  error BCMTSA_SpotLimitPriceTooLow();
  error BCMTSA_SellingTooMuchCollateral();
  error BCMTSA_FeeTooHigh();
  error BCMTSA_MustHaveNegativeCash();
}
