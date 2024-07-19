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
import "./CollateralManagementTSA.sol";

/// @title CoveredCallTSA
/// @notice TSA that accepts any deposited collateral, and sells covered calls on it. Assumes options sold are
/// directionally similar to the collateral (i.e. LRT selling ETH covered calls).
/// @dev Only one "hash" can be valid at a time, so the state of the contract can be checked easily, without needing to
/// worry about multiple different transactions all executing simultaneously.
contract CoveredCallTSA is CollateralManagementTSA {
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
    /// @dev The worst difference to vol that is accepted for pricing options (e.g. 0.9e18)
    uint optionVolSlippageFactor;
    /// @dev The highest delta for options accepted by the TSA after vol/fwd slippage is applied (e.g. 0.15e18).
    uint optionMaxDelta;
    /// @dev Maximum amount of negative cash allowed to be held to open any more option positions. (e.g. -100e18)
    int optionMaxNegCash;
    /// @dev Lower bound for option expiry
    uint optionMinTimeToExpiry;
    /// @dev Upper bound for option expiry
    uint optionMaxTimeToExpiry;
  }

  /// @custom:storage-location erc7201:lyra.storage.CoveredCallTSA
  struct CCTSAStorage {
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
    ISpotFeed baseFeed;
    CCTSAParams ccParams;
    CollateralManagementParams collateralManagementParams;
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

    $.depositModule = ccInitParams.depositModule;
    $.withdrawalModule = ccInitParams.withdrawalModule;
    $.tradeModule = ccInitParams.tradeModule;
    $.optionAsset = ccInitParams.optionAsset;
    $.baseFeed = ccInitParams.baseFeed;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setCCTSAParams(CollateralManagementParams memory newCollateralMngmtParams, CCTSAParams memory newParams)
    external
    onlyOwner
  {
    if (
      newParams.minSignatureExpiry < 1 minutes || newParams.minSignatureExpiry > newParams.maxSignatureExpiry
        || newCollateralMngmtParams.worstSpotBuyPrice < 1e18 || newCollateralMngmtParams.worstSpotBuyPrice > 1.2e18
        || newCollateralMngmtParams.worstSpotSellPrice > 1e18 || newCollateralMngmtParams.worstSpotSellPrice < 0.8e18
        || newCollateralMngmtParams.spotTransactionLeniency < 1e18
        || newCollateralMngmtParams.spotTransactionLeniency > 1.2e18 || newParams.optionVolSlippageFactor > 1e18
        || newParams.optionMaxDelta >= 0.5e18 || newParams.optionMaxTimeToExpiry <= newParams.optionMinTimeToExpiry
        || newParams.optionMaxNegCash > 0 || newCollateralMngmtParams.feeFactor > 0.05e18
    ) {
      revert CCT_InvalidParams();
    }
    _getCCTSAStorage().ccParams = newParams;
    _getCCTSAStorage().collateralManagementParams = newCollateralMngmtParams;

    emit CCTSAParamsSet(newParams, newCollateralMngmtParams);
  }

  function _getCollateralManagementParams() internal view override returns (CollateralManagementParams storage $) {
    return _getCCTSAStorage().collateralManagementParams;
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
      _tradeCollateral(tradeData);
    } else if (tradeData.asset == address(_getCCTSAStorage().optionAsset)) {
      if (tradeData.isBid) {
        revert CCT_CanOnlyOpenShortOptions();
      }
      _verifyOptionSell(tradeData);
    } else {
      revert CCT_InvalidAsset();
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

    _verifyCollateralTradeFee(tradeData.worstFee, _getBasePrice());
    _validateOptionDetails(tradeData.subId.toUint96(), tradeData.limitPrice.toUint256());
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
    (uint callPrice,, uint callDelta) = _getOptionPrice(expiry, strike);

    if (callDelta > $.ccParams.optionMaxDelta) {
      revert CCT_OptionDeltaTooHigh();
    }

    if (limitPrice <= callPrice) {
      revert CCT_OptionPriceTooLow();
    }
  }

  function _getOptionPrice(uint optionExpiry, uint optionStrike)
    internal
    view
    returns (uint callPrice, uint putPrice, uint callDelta)
  {
    CCTSAStorage storage $ = _getCCTSAStorage();
    uint timeToExpiry = optionExpiry - block.timestamp;
    if (timeToExpiry < $.ccParams.optionMinTimeToExpiry || timeToExpiry > $.ccParams.optionMaxTimeToExpiry) {
      revert CCT_OptionExpiryOutOfBounds();
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

  function _getBasePrice() internal view override returns (uint spotPrice) {
    (spotPrice,) = _getCCTSAStorage().baseFeed.getSpot();
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

  function getCollateralManagementParams() public view returns (CollateralManagementParams memory) {
    return _getCollateralManagementParams();
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
  event CCTSAParamsSet(CCTSAParams params, CollateralManagementParams collateralManagementParams);

  error CCT_InvalidParams();
  error CCT_InvalidActionExpiry();
  error CCT_InvalidModule();
  error CCT_InvalidAsset();
  error CCT_DepositingTooMuch();
  error CCT_WithdrawingUtilisedCollateral();
  error CCT_WithdrawalNegativeCash();
  error CCT_SellingTooManyCalls();
  error CCT_CannotSellOptionsWithNegativeCash();
  error CCT_OnlyShortCallsAllowed();
  error CCT_OptionExpired();
  error CCT_OptionDeltaTooHigh();
  error CCT_OptionPriceTooLow();
  error CCT_InvalidOptionBalance();
  error CCT_InvalidDesiredAmount();
  error CCT_CanOnlyOpenShortOptions();
  error CCT_OptionExpiryOutOfBounds();
}
