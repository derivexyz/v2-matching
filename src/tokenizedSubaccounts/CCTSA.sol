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
import {ITradeModule} from "../interfaces/ITradeModule.sol";
import {IMatching} from "../interfaces/IMatching.sol";

import {
  StandardManager, IStandardManager, IVolFeed, IForwardFeed
} from "v2-core/src/risk-managers/StandardManager.sol";

/// @title CoveredCallTSA
/// @notice TSA that accepts any deposited collateral, and sells covered calls on it. Assumes options sold are
/// directionally similar to the collateral (i.e. LRT selling ETH covered calls).
/// @dev Only one "hash" can be valid at a time, so the state of the contract can be checked easily, without needing to
/// worry about multiple different transactions all executing simultaneously.
contract CoveredCallTSA is BaseOnChainSigningTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct CCTSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
  }

  struct CCTSAParams {
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
    /// @dev The highest delta for options accepted by the TSA after vol/fwd slippage is applied (e.g. 0.15e18).
    uint optionMaxDelta;
    /// @dev Lower bound for option expiry
    uint optionMinTimeToExpiry;
    /// @dev Upper bound for option expiry
    uint optionMaxTimeToExpiry;
    /// @dev Maximum amount of negative cash allowed to be held to open any more option positions. (e.g. -100e18)
    int optionMaxNegCash;
    /// @dev Percentage of spot that can be paid as a fee for both spot/options (e.g. 0.01e18)
    uint feeFactor;
  }

  /// @custom:storage-location erc7201:lyra.storage.CoveredCallTSA
  struct CCTSAStorage {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
    CCTSAParams ccParams;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    bytes32 lastSeenHash;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.CoveredCallTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant CCTSAStorageLocation = 0x1a4655c7c13a97bb1cd1d7862ecec4d101efff348d9aee723006797984c8e700;

  function _getCCTSAStorage() private pure returns (CCTSAStorage storage $) {
    assembly {
      $.slot := CCTSAStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    BaseTSA.BaseTSAInitParams memory initParams,
    CCTSAInitParams memory ccInitParams
  ) external reinitializer(2) {
    __BaseTSA_init(initialOwner, initParams);

    CCTSAStorage storage $ = _getCCTSAStorage();

    $.baseFeed = ccInitParams.baseFeed;

    $.depositModule = ccInitParams.depositModule;
    $.withdrawalModule = ccInitParams.withdrawalModule;
    $.tradeModule = ccInitParams.tradeModule;
    $.optionAsset = ccInitParams.optionAsset;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setCCTSAParams(CCTSAParams memory newParams) external onlyOwner {
    if (
      newParams.minSignatureExpiry < 1 minutes || newParams.minSignatureExpiry > newParams.maxSignatureExpiry
        || (newParams.worstSpotBuyPrice < 1e18 || newParams.worstSpotBuyPrice > 1.2e18)
        || (newParams.worstSpotSellPrice > 1e18 || newParams.worstSpotSellPrice < 0.8e18)
        || (newParams.spotTransactionLeniency < 1e18 || newParams.spotTransactionLeniency > 1.2e18)
        || newParams.optionVolSlippageFactor > 1e18 || newParams.optionMaxDelta >= 0.5e18
        || newParams.optionMaxTimeToExpiry <= newParams.optionMinTimeToExpiry || newParams.optionMaxNegCash > 0
        || newParams.feeFactor > 0.05e18
    ) {
      revert CCT_InvalidParams();
    }

    _getCCTSAStorage().ccParams = newParams;

    emit CCTSAParamsSet(newParams);
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory /* extraData */ )
    internal
    virtual
    override
  {
    CCTSAStorage storage $ = _getCCTSAStorage();

    if (
      action.expiry < block.timestamp + $.ccParams.minSignatureExpiry
        || action.expiry > block.timestamp + $.ccParams.maxSignatureExpiry
    ) {
      revert CCT_InvalidActionExpiry();
    }

    // Disable last seen hash when a new one comes in.
    // We dont want to have to track pending withdrawals etc. in the logic, and work out if when they've been executed
    _revokeSignature($.lastSeenHash);
    $.lastSeenHash = actionHash;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    if (address(action.module) == address($.depositModule)) {
      _verifyDepositAction(action, tsaAddresses);
    } else if (address(action.module) == address($.withdrawalModule)) {
      _verifyWithdrawAction(action, tsaAddresses);
    } else if (address(action.module) == address($.tradeModule)) {
      _verifyTradeAction(action, tsaAddresses);
    } else {
      revert CCT_InvalidModule();
    }
  }

  //////////////
  // Deposits //
  //////////////

  function _verifyDepositAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IDepositModule.DepositData memory depositData = abi.decode(action.data, (IDepositModule.DepositData));

    if (depositData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert CCT_InvalidAsset();
    }

    if (depositData.amount > tsaAddresses.depositAsset.balanceOf(address(this)) - totalPendingDeposits()) {
      revert CCT_DepositingTooMuch();
    }
  }

  /////////////////
  // Withdrawals //
  /////////////////

  function _verifyWithdrawAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    if (withdrawalData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert CCT_InvalidAsset();
    }

    (uint numShortCalls, uint baseBalance, int cashBalance) = _getSubAccountStats();

    uint amount18 = ConvertDecimals.to18Decimals(withdrawalData.assetAmount, tsaAddresses.depositAsset.decimals());

    if (baseBalance < amount18 + numShortCalls) {
      revert CCT_WithdrawingUtilisedCollateral();
    }

    if (cashBalance < _getCCTSAStorage().ccParams.optionMaxNegCash) {
      revert CCT_WithdrawalNegativeCash();
    }
  }

  /////////////
  // Trading //
  /////////////

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    if (tradeData.desiredAmount <= 0) {
      revert CCT_InvalidDesiredAmount();
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
    } else if (tradeData.asset == address(_getCCTSAStorage().optionAsset)) {
      if (tradeData.isBid) {
        revert CCT_CanOnlyOpenShortOptions();
      }
      _verifyOptionSell(tradeData);
    } else {
      revert CCT_InvalidAsset();
    }
  }

  function _verifyCollateralBuy(ITradeModule.TradeData memory tradeData, BaseTSAAddresses memory tsaAddresses)
    internal
    view
  {
    CCTSAStorage storage $ = _getCCTSAStorage();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance <= 0) {
      revert CCT_MustHavePositiveCash();
    }
    uint basePrice = _getBasePrice();

    // We don't worry too much about the fee in the calculations, as we trust the exchange won't cause issues. We make
    // sure max fee doesn't exceed 0.5% of spot though.
    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() > basePrice.multiplyDecimal($.ccParams.worstSpotBuyPrice)) {
      revert CCT_SpotLimitPriceTooHigh();
    }

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal($.ccParams.spotTransactionLeniency);
    if (cost > bufferedBalance) {
      revert CCT_BuyingTooMuchCollateral();
    }
  }

  function _verifyCollateralSell(ITradeModule.TradeData memory tradeData, BaseTSAAddresses memory tsaAddresses)
    internal
    view
  {
    CCTSAStorage storage $ = _getCCTSAStorage();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance >= 0) {
      revert CCT_MustHaveNegativeCash();
    }

    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() < basePrice.multiplyDecimal($.ccParams.worstSpotSellPrice)) {
      revert CCT_SpotLimitPriceTooLow();
    }

    // cost is positive, balance is negative
    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal($.ccParams.spotTransactionLeniency);

    // We make sure we're not selling more $ value of collateral than we have in debt
    if (cost.abs() > bufferedBalance.abs()) {
      revert CCT_SellingTooMuchCollateral();
    }
  }

  /**
   * @dev verifies:
   * - amount of options wont exceed base balance
   * - delta of option is above threshold
   * - limit price is within acceptable bounds
   */
  function _verifyOptionSell(ITradeModule.TradeData memory tradeData) internal view {
    (uint numShortCalls, uint baseBalance, int cashBalance) = _getSubAccountStats();

    if (tradeData.desiredAmount.abs() + numShortCalls > baseBalance) {
      revert CCT_SellingTooManyCalls();
    }

    if (cashBalance < _getCCTSAStorage().ccParams.optionMaxNegCash) {
      revert CCT_CannotSellOptionsWithNegativeCash();
    }

    _verifyFee(tradeData.worstFee, _getBasePrice());
    _validateOptionDetails(tradeData.subId.toUint96(), tradeData.limitPrice.toUint256());
  }

  function _verifyFee(uint worstFee, uint basePrice) internal view {
    CCTSAStorage storage $ = _getCCTSAStorage();

    if (worstFee > basePrice.multiplyDecimal($.ccParams.feeFactor)) {
      revert CCT_FeeTooHigh();
    }
  }

  /////////////////
  // Option Math //
  /////////////////

  function _validateOptionDetails(uint96 subId, uint limitPrice) internal view {
    CCTSAStorage storage $ = _getCCTSAStorage();

    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId);
    if (!isCall) {
      revert CCT_OnlyShortCallsAllowed();
    }
    if (block.timestamp >= expiry) {
      revert CCT_OptionExpired();
    }
    uint timeToExpiry = expiry - block.timestamp;
    if (timeToExpiry < $.ccParams.optionMinTimeToExpiry || timeToExpiry > $.ccParams.optionMaxTimeToExpiry) {
      revert CCT_OptionExpiryOutOfBounds();
    }

    (uint vol, uint forwardPrice) = _getFeedValues(strike.toUint128(), expiry.toUint64());

    (uint callPrice,, uint callDelta) = Black76.pricesAndDelta(
      Black76.Black76Inputs({
        timeToExpirySec: timeToExpiry.toUint64(),
        volatility: (vol.multiplyDecimal($.ccParams.optionVolSlippageFactor)).toUint128(),
        fwdPrice: forwardPrice.toUint128(),
        strikePrice: strike.toUint128(),
        discount: 1e18
      })
    );

    if (callDelta > $.ccParams.optionMaxDelta) {
      revert CCT_OptionDeltaTooHigh();
    }

    if (limitPrice <= callPrice) {
      revert CCT_OptionPriceTooLow();
    }
  }

  function _getFeedValues(uint128 strike, uint64 expiry) internal view returns (uint vol, uint forwardPrice) {
    CCTSAStorage storage $ = _getCCTSAStorage();

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
      revert CCT_PositionInsolvent();
    }

    return uint(convertedMtM) + depositAssetBalance;
  }

  /// @notice Get the number of short calls, base balance and cash balance of the subaccount. Ignores any assets held
  /// on this contract itself (pending deposits and erc20 held but not deposited to subaccount)
  function _getSubAccountStats() internal view returns (uint numShortCalls, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getCCTSAStorage().optionAsset) {
        int balance = balances[i].balance;
        if (balance > 0) {
          revert CCT_InvalidOptionBalance();
        }
        numShortCalls += balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    return (numShortCalls, baseBalance, cashBalance);
  }

  function _getBasePrice() internal view returns (uint) {
    (uint spotPrice,) = _getCCTSAStorage().baseFeed.getSpot();
    return spotPrice;
  }

  ///////////
  // Views //
  ///////////

  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }

  function getSubAccountStats() public view returns (uint numShortCalls, uint baseBalance, int cashBalance) {
    return _getSubAccountStats();
  }

  function getBasePrice() public view returns (uint) {
    return _getBasePrice();
  }

  function getCCTSAParams() public view returns (CCTSAParams memory) {
    return _getCCTSAStorage().ccParams;
  }

  function lastSeenHash() public view returns (bytes32) {
    return _getCCTSAStorage().lastSeenHash;
  }

  function getCCTSAAddresses()
    public
    view
    returns (ISpotFeed, IDepositModule, IWithdrawalModule, ITradeModule, IOptionAsset)
  {
    CCTSAStorage storage $ = _getCCTSAStorage();
    return ($.baseFeed, $.depositModule, $.withdrawalModule, $.tradeModule, $.optionAsset);
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event CCTSAParamsSet(CCTSAParams params);

  error CCT_InvalidParams();
  error CCT_InvalidActionExpiry();
  error CCT_InvalidModule();
  error CCT_InvalidAsset();
  error CCT_DepositingTooMuch();
  error CCT_WithdrawingUtilisedCollateral();
  error CCT_WithdrawalNegativeCash();
  error CCT_SellingTooManyCalls();
  error CCT_CannotSellOptionsWithNegativeCash();
  error CCT_FeeTooHigh();
  error CCT_OnlyShortCallsAllowed();
  error CCT_OptionExpired();
  error CCT_OptionExpiryOutOfBounds();
  error CCT_OptionDeltaTooHigh();
  error CCT_OptionPriceTooLow();
  error CCT_PositionInsolvent();
  error CCT_InvalidOptionBalance();
  error CCT_InvalidDesiredAmount();
  error CCT_CanOnlyOpenShortOptions();
  error CCT_MustHavePositiveCash();
  error CCT_BuyingTooMuchCollateral();
  error CCT_SpotLimitPriceTooHigh();
  error CCT_MustHaveNegativeCash();
  error CCT_SellingTooMuchCollateral();
  error CCT_SpotLimitPriceTooLow();
}
