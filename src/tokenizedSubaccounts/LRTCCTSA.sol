// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

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

/// @title LRTCCTSA
/// @notice TSA that accepts LRTs as deposited collateral, and sells covered calls.
/// @dev Prices shares in USD, but accepts baseAsset as deposit. Vault intended to try remain delta neutral.
contract LRTCCTSA is BaseOnChainSigningTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct LRTCCTSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
  }

  struct LRTCCTSAParams {
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


  struct LRTCCTSAStorage {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;

    LRTCCTSAParams ccParams;

    bytes32 lastSeenHash;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.LRTCCTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant LRTCCTSAStorageLocation = 0xd23c9568c865fed3eccfc1638328efd8f43b198d4d62e7fa8b700b08a8282300;

  function _getLRTCCTSAStorage() private pure returns (LRTCCTSAStorage storage $) {
    assembly {
      $.slot := LRTCCTSAStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address initialOwner, BaseTSA.BaseTSAInitParams memory initParams, LRTCCTSAInitParams memory lrtCcParams) external reinitializer(2) {
    __BaseTSA_init(initialOwner, initParams);

    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    $.baseFeed = lrtCcParams.baseFeed;

    $.depositModule = lrtCcParams.depositModule;
    $.withdrawalModule = lrtCcParams.withdrawalModule;
    $.tradeModule = lrtCcParams.tradeModule;
    $.optionAsset = lrtCcParams.optionAsset;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setLRTCCTSAParams(LRTCCTSAParams memory newParams) external onlyOwner {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    $.ccParams = newParams;
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash) internal virtual override {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    require(action.expiry >= block.timestamp + $.ccParams.minSignatureExpiry, "Action expiry too soon");
    require(action.expiry <= block.timestamp + $.ccParams.maxSignatureExpiry, "Action expiry too far");

    // Disable last seen hash when a new one comes in.
    // We dont want to have to track pending withdrawals etc. in the logic, and work out if when they've been executed
    _revokeSignature($.lastSeenHash);
    $.lastSeenHash = actionHash;

    if (address(action.module) == address($.depositModule)) {
      _verifyDepositAction(action);
    } else if (address(action.module) == address($.withdrawalModule)) {
      _verifyWithdrawAction(action);
    } else if (address(action.module) == address($.tradeModule)) {
      _verifyTradeAction(action);
    } else {
      revert("LRTCCTSA: Invalid module");
    }
  }

  //////////////
  // Deposits //
  //////////////

  function _verifyDepositAction(IMatching.Action memory action) internal view {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    IDepositModule.DepositData memory depositData = abi.decode(action.data, (IDepositModule.DepositData));
    if (depositData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert("LRTCCTSA: Invalid asset");
    }
  }

  /////////////////
  // Withdrawals //
  /////////////////

  function _verifyWithdrawAction(IMatching.Action memory action) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));
    if (withdrawalData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert("LRTCCTSA: Invalid asset");
    }

    (uint numShortCalls, uint baseBalance, int cashBalance) = _getAccountStats();
    if (numShortCalls > baseBalance + withdrawalData.assetAmount) {
      revert("LRTCCTSA: Cannot withdraw utilised collateral");
    }

    if (cashBalance < $.ccParams.optionMaxNegCash) {
      revert("LRTCCTSA: Cannot withdraw with negative cash");
    }
  }

  /////////////
  // Trading //
  /////////////

  function _verifyTradeAction(IMatching.Action memory action) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();


    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    if (tradeData.asset == address(tsaAddresses.wrappedDepositAsset)) {
      if (tradeData.isBid) {
        // Buying more LRTs with excess cash
        _verifyLRTBuy(tradeData);
      } else {
        // Selling LRTs to cover cash debt
        _verifyLRTSell(tradeData);
      }
      return;
    } else if (tradeData.asset == address($.optionAsset)) {
      require(!tradeData.isBid, "LRTCCTSA: Can only open short positions");

      _verifyOptionSell(tradeData);
    } else {
      revert("LRTCCTSA: Invalid asset");
    }
  }

  function _verifyLRTBuy(ITradeModule.TradeData memory tradeData) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();


    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    require(cashBalance > 0, "LRTCCTSA: Can only buy with positive cash");

    uint basePrice = _getBasePrice();

    // We don't worry too much about the fee in the calculations, as we trust the exchange won't cause issues. We make
    // sure max fee doesn't exceed 0.5% of spot though.
    _verifyFee(tradeData.worstFee, basePrice);
    require(tradeData.limitPrice.toUint256() <= basePrice.multiplyDecimal($.ccParams.worstSpotBuyPrice));

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    require(
      cost < cashBalance.multiplyDecimal($.ccParams.spotTransactionLeniency), "LRTCCTSA: Buying too much collateral"
    );
  }

  function _verifyLRTSell(ITradeModule.TradeData memory tradeData) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();


    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    require(cashBalance < 0, "LRTCCTSA: Can only buy with positive cash");

    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.worstFee, basePrice);
    require(tradeData.limitPrice.toUint256() >= basePrice.multiplyDecimal($.ccParams.worstSpotSellPrice));

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    require(
      cost < cashBalance.multiplyDecimal($.ccParams.spotTransactionLeniency), "LRTCCTSA: Selling too much collateral"
    );
  }

  function _verifyOptionSell(ITradeModule.TradeData memory tradeData) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    // verify:
    // - amount of options wont exceed base balance
    // - delta of option is above threshold
    // - limit price is within acceptable bounds

    (uint numShortCalls, uint baseBalance, int cashBalance) = _getAccountStats();
    require(tradeData.desiredAmount.abs() + numShortCalls <= baseBalance, "LRTCCTSA: Selling too many calls");
    if (cashBalance < $.ccParams.optionMaxNegCash) {
      revert("LRTCCTSA: Cannot sell options with negative cash");
    }

    _validateOptionDetails(tradeData.subId.toUint96(), tradeData.limitPrice.toUint256());
  }

  function _verifyFee(uint worstFee, uint basePrice) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    require(worstFee < basePrice.multiplyDecimal($.ccParams.feeFactor), "LRTCCTSA: Fee too high");
  }

  /////////////////
  // Option Math //
  /////////////////

  function _validateOptionDetails(uint96 subId, uint limitPrice) internal view {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId);
    require(isCall, "LRTCCTSA: Only short calls allowed");

    if (block.timestamp >= expiry) {
      revert("LRTCCTSA: Option expired");
    }
    uint timeToExpiry = expiry - block.timestamp;
    if (timeToExpiry < $.ccParams.optionMinTimeToExpiry || timeToExpiry > $.ccParams.optionMaxTimeToExpiry) {
      revert("LRTCCTSA: Option expiry out of bounds");
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

    if (callDelta < $.ccParams.optionMaxDelta) {
      revert("LRTCCTSA: Option delta too low");
    }

    if (callPrice < limitPrice) {
      revert("LRTCCTSA: Option price too low");
    }
  }

  function _getFeedValues(uint128 strike, uint64 expiry) internal view returns (uint vol, uint forwardPrice) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    StandardManager srm = StandardManager(address(tsaAddresses.manager));
    IStandardManager.AssetDetail memory assetDetails = srm.assetDetails($.optionAsset);
    (, IForwardFeed fwdFeed, IVolFeed volFeed) = srm.getMarketFeeds(assetDetails.marketId);
    (vol,) = volFeed.getVol(strike, expiry);
    (forwardPrice,) = fwdFeed.getForwardPrice(expiry);
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getAccountValue() internal view override returns (uint) {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    // TODO: double check perp Pnl, funding, cash interest is accounted for
    uint depositAssetBalance = tsaAddresses.depositAsset.balanceOf(address(this)) - totalPendingDeposits();

    (, int mtm) = tsaAddresses.manager.getMarginAndMarkToMarket(subAccount(), true, 0);
    (uint spotPrice,) = $.baseFeed.getSpot();

    int convertedMtM = mtm.divideDecimal(spotPrice.toInt256());

    if (convertedMtM < 0 && depositAssetBalance < convertedMtM.abs()) {
      revert("LRTCCTSA: Position insolvent");
    }

    return (convertedMtM + depositAssetBalance.toInt256()).abs();
  }

  function _getAccountStats() internal view returns (uint numShortCalls, uint baseBalance, int cashBalance) {
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == $.optionAsset) {
        int balance = balances[i].balance;
        if (balance > 0) {
          revert("LRTCCTSA: Invalid option balance");
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
    LRTCCTSAStorage storage $ = _getLRTCCTSAStorage();

    (uint spotPrice,) = $.baseFeed.getSpot();
    return spotPrice;
  }
}
