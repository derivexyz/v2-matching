// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./EmptyTSA.sol";

abstract contract CollateralManagementTSA is EmptyTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct CollateralManagementParams {
    /// @dev Percentage of spot that can be paid as a fee for both spot/options (e.g. 0.01e18)
    uint feeFactor;
    /// @dev A factor on how strict to be with preventing too much cash being used in swapping base asset (e.g. 1.01e18)
    int spotTransactionLeniency;
    /// @dev Percentage of spot price that the TSA will sell baseAsset at in the worst case (e.g. 0.98e18)
    uint worstSpotSellPrice;
    /// @dev Percentage of spot price that the TSA will buy baseAsset at in the worst case (e.g. 1.02e18)
    uint worstSpotBuyPrice;
  }

  ///////////////////
  //     Admin     //
  ///////////////////
  function setCollateralManagementParams(CollateralManagementParams memory newCollateralMgmtParams) external virtual;

  function _getCollateralManagementParams() internal view virtual returns (CollateralManagementParams storage $);

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
    CollateralManagementParams storage baseParams = _getCollateralManagementParams();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance <= 0) {
      revert CMTSA_MustHavePositiveCash();
    }
    uint basePrice = _getBasePrice();

    // We don't worry too much about the fee in the calculations, as we trust the exchange won't cause issues. We make
    // sure max fee doesn't exceed 0.5% of spot though.
    _verifyCollateralTradeFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() > basePrice.multiplyDecimal(baseParams.worstSpotBuyPrice)) {
      revert CMTSA_SpotLimitPriceTooHigh();
    }

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal(baseParams.spotTransactionLeniency);
    if (cost > bufferedBalance) {
      revert CMTSA_BuyingTooMuchCollateral();
    }
  }

  function _verifyCollateralSell(ITradeModule.TradeData memory tradeData) internal view {
    CollateralManagementParams storage baseParams = _getCollateralManagementParams();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance >= 0) {
      revert CMTSA_MustHaveNegativeCash();
    }

    uint basePrice = _getBasePrice();

    _verifyCollateralTradeFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() < basePrice.multiplyDecimal(baseParams.worstSpotSellPrice)) {
      revert CMTSA_SpotLimitPriceTooLow();
    }

    // cost is positive, balance is negative
    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal(baseParams.spotTransactionLeniency);

    // We make sure we're not selling more $ value of collateral than we have in debt
    if (cost.abs() > bufferedBalance.abs()) {
      revert CMTSA_SellingTooMuchCollateral();
    }
  }

  function _verifyCollateralTradeFee(uint worstFee, uint basePrice) internal view {
    CollateralManagementParams storage baseParams = _getCollateralManagementParams();

    if (worstFee > basePrice.multiplyDecimal(baseParams.feeFactor)) {
      revert CMTSA_FeeTooHigh();
    }
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event CMTSAParamsSet(CollateralManagementParams collateralManagementParams);

  error CMTSA_MustHavePositiveCash();
  error CMTSA_SpotLimitPriceTooHigh();
  error CMTSA_BuyingTooMuchCollateral();
  error CMTSA_SpotLimitPriceTooLow();
  error CMTSA_SellingTooMuchCollateral();
  error CMTSA_FeeTooHigh();
  error CMTSA_MustHaveNegativeCash();
}
