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

/// @title Day to Expiration Exchange TSA
/// @notice TSA that accepts any deposited collateral and allows users to sell covered calls, buy calls, sell puts, and buy puts
/// @dev Only one "hash" can be valid at a time, so the state of the contract can be checked easily, without needing to
/// worry about multiple different transactions all executing simultaneously.
contract DTETSA is CollateralManagementTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  // Enum to represent option types
  enum OptionType {
    CALL,
    PUT
  }

  // Enum to represent option actions
  enum OptionAction {
    BUY,
    SELL
  }

  struct DTETSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
  }

  struct DTETSAParams {
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
    /// @dev Maximum number of options that can be sold against the collateral
    uint maxOptionsToCollateralRatio;
  }

  /// @custom:storage-location erc7201:lyra.storage.DigitalTokenizedExchangeTSA
  struct DTETSAStorage {
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
    ISpotFeed baseFeed;
    IMatching matching;
    DTETSAParams dteParams;
    CollateralManagementParams collateralManagementParams;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    bytes32 lastSeenHash;
    /// @dev Track user option positions by subId and action type
    /// @dev Format: userOptionPositions[user][subId][actionType]
    /// @dev actionType: 0 = buy, 1 = sell
    mapping(address => mapping(uint96 => mapping(uint8 => int256))) userOptionPositions;
    /// @dev Array to store pending trade data
    ITradeModule.TradeData[] pendingTrades;
    /// @dev Count of pending trades
    uint pendingTradeCount;
    /// @dev Track user shares
    mapping(address => uint256) userShares;
  }
  //@todo : need to update it 
  // keccak256(abi.encode(uint256(keccak256("lyra.storage.DigitalTokenizedExchangeTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant DTETSAStorageLocation = 0x2b4655c7c13a97bb1cd1d7862ecec4d101efff348d9aee723006797984c8e700;

   // keccak256(abi.encode(uint256(keccak256("lyra.storage.BaseTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant BaseTSAStorageLocation = 0x5dfed237c807655691d61cacf0fafd8d8cac98f5cca2d37d7fc033aa25733b00;

  function _getBaseTSAStorage() private pure override returns (BaseTSAStorage storage $) {
    assembly {
      $.slot := BaseTSAStorageLocation
    }
  }

  function _getDTETSAStorage() private pure returns (DTETSAStorage storage $) {
    assembly {
      $.slot := DTETSAStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    BaseTSA.BaseTSAInitParams memory initParams,
    DTETSAInitParams memory dteInitParams
  ) external reinitializer(5) {
    __BaseTSA_init(initialOwner, initParams);

    DTETSAStorage storage $ = _getDTETSAStorage();

    $.depositModule = dteInitParams.depositModule;
    $.withdrawalModule = dteInitParams.withdrawalModule;
    $.tradeModule = dteInitParams.tradeModule;
    $.optionAsset = dteInitParams.optionAsset;
    $.baseFeed = dteInitParams.baseFeed;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  // Admin //

  function setDTETSAParams(DTETSAParams memory newParams) external onlyOwner {
    if (
      newParams.minSignatureExpiry < 1 minutes || newParams.minSignatureExpiry > newParams.maxSignatureExpiry
        || newParams.optionVolSlippageFactor > 1e18 || newParams.optionMaxDelta >= 0.5e18
        || newParams.optionMaxTimeToExpiry <= newParams.optionMinTimeToExpiry || newParams.optionMaxNegCash > 0
        || newParams.maxOptionsToCollateralRatio > 1e18
    ) {
      revert DTE_InvalidParams();
    }
    _getDTETSAStorage().dteParams = newParams;

    emit DTETSAParamsSet(newParams);
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
      revert DTE_InvalidParams();
    }
    _getDTETSAStorage().collateralManagementParams = newCollateralMgmtParams;

    emit CMTSAParamsSet(newCollateralMgmtParams);
  }

  function _getCollateralManagementParams() internal view override returns (CollateralManagementParams storage $) {
    return _getDTETSAStorage().collateralManagementParams;
  }

  function _processDeposit(uint256 depositId) internal override {
      super._processDeposit(depositId);

      DTETSAStorage storage $ = _getDTETSAStorage();
      BaseTSAStorage storage $B = _getBaseTSAStorage();
      
      DepositRequest storage request = $B.queuedDeposit[depositId];
      $.userShares[msg.sender] += request.sharesReceived;
  }


  function processWithdrawalRequests(uint256 limit) external override checkBlocked onlyShareKeeper nonReentrant {
      _collectFee();
      DTETSAStorage storage $ = _getDTETSAStorage();
      BaseTSAStorage storage $B = _getBaseTSAStorage();

      for (uint256 i = 0; i < limit; ++i) {
          if ($B.queuedWithdrawalHead >= $B.nextQueuedWithdrawalId) {
              break;
          }

          WithdrawalRequest storage request = $B.queuedWithdrawals[$B.queuedWithdrawalHead];

          uint256 totalBalance = $B.depositAsset.balanceOf(address(this)) - $B.totalPendingDeposits;
          uint256 requiredAmount = _getSharesToWithdrawAmount(request.amountShares);

          if (totalBalance == 0) {
              break;
          }

          if (totalBalance < requiredAmount) {
              uint256 withdrawAmount = totalBalance;
              uint256 difference = requiredAmount - withdrawAmount;
              uint256 finalShareAmount = request.amountShares * difference / requiredAmount;
              uint256 sharesRedeemed = request.amountShares - finalShareAmount;

              $B.totalPendingWithdrawals -= sharesRedeemed;
              request.amountShares = finalShareAmount;
              request.assetsReceived += withdrawAmount;
              // Update user's shares - subtract the actual number of shares being withdrawn
              $.userShares[request.beneficiary] -= sharesRedeemed;

              emit WithdrawalProcessed(
                  $B.queuedWithdrawalHead, request.beneficiary, false, sharesRedeemed, withdrawAmount
              );

              $B.depositAsset.transfer(request.beneficiary, withdrawAmount);
              

              break;
          } else {
              uint256 sharesRedeemed = request.amountShares;

              $B.totalPendingWithdrawals -= sharesRedeemed;
              request.amountShares = 0;
              request.assetsReceived += requiredAmount;


              // Update user's shares - subtract the actual number of shares being withdrawn
              $.userShares[request.beneficiary] -= sharesRedeemed;

              emit WithdrawalProcessed(
                  $B.queuedWithdrawalHead, request.beneficiary, true, sharesRedeemed, requiredAmount
              );

              $B.depositAsset.transfer(request.beneficiary, requiredAmount);
          }
          $B.queuedWithdrawalHead++;
      }
  }
    
    
  // Option Position Functions //


  /**
   * @notice Open an option position
   * @param subId The option subId
   * @param amount The amount to trade
   * @param isBid Whether this is a bid (buy) or ask (sell)
   */
  function openOptionPosition(uint96 subId, uint256 amount, bool isBid) external checkBlocked nonReentrant {
    DTETSAStorage storage $ = _getDTETSAStorage();
    
    // Create trade data
    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address($.optionAsset),
      subId: subId,
      isBid: isBid,
      desiredAmount: int(amount),
      limitPrice: 0, // Will be filled by matching engine
      worstFee: 0, // Will be filled by matching engine
      recipientId: subAccount() // Use the contract's subaccount ID as recipient
    });
    
    // Verify the trade
    _verifyOptionTrade(tradeData);

    // Decode option details from subId
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId);
    
    // Determine action type (0 = buy, 1 = sell)
    uint8 actionType = isBid ? 0 : 1;
    
    // Calculate premium and margin requirements
    (uint256 premium, uint256 marginRequired) = _calculateOptionPrice(expiry, strike, isCall, isBid);
    
    // Get current share price
    uint256 sharePrice = _getSharePrice();
    
    if (isBid) {
      // For buying options (long position)
      // Only need to pay the premium
      uint256 totalCost = (premium * amount) / 1e18;
      uint256 sharesToDeduct = (totalCost * 1e18) / sharePrice;
      
      // Check if user has enough shares
      if ($.userShares[msg.sender] < sharesToDeduct) {
        revert DTE_InsufficientShares();
      }
      
      // Update user's shares - deduct premium
      $.userShares[msg.sender] -= sharesToDeduct;
      
      // Update user position
      $.userOptionPositions[msg.sender][subId][actionType] += int256(amount);
      
      emit OptionPositionOpened(msg.sender, subId, amount, true, totalCost);
    } else {
      // For selling options (short position)
      // Need to handle both premium and margin
      uint256 premiumAmount = (premium * amount) / 1e18;
      uint256 marginAmount = (marginRequired * amount) / 1e18;
      
      // Convert premium to shares and credit to user
      uint256 premiumShares = (premiumAmount * 1e18) / sharePrice;
      
      // Convert margin to shares and debit from user
      uint256 marginShares = (marginAmount * 1e18) / sharePrice;
      
      // Check if user has enough shares for margin
      if ($.userShares[msg.sender] < marginShares) {
        revert DTE_InsufficientShares();
      }
      
      // Update user's shares
      $.userShares[msg.sender] += premiumShares;
      $.userShares[msg.sender] -= marginShares;
      
      // Update user position
      $.userOptionPositions[msg.sender][subId][actionType] -= int256(amount);
      
      emit OptionPositionOpened(msg.sender, subId, amount, false, marginAmount);
    }
    
    // Store trade data in array
    $.pendingTrades.push(tradeData);
    $.pendingTradeCount++;
  }

  /**
   * @notice Close an option position
   * @param subId The option subId
   * @param amount The amount to close
   * @param isBid Whether this is a bid (buy) or ask (sell)
   */
  function closeOptionPosition(uint96 subId, uint256 amount, bool isBid) external checkBlocked nonReentrant {
    DTETSAStorage storage $ = _getDTETSAStorage();
    
    // Create trade data
    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address($.optionAsset),
      subId: subId,
      isBid: isBid,
      desiredAmount: int(amount),
      limitPrice: 0, // Will be filled by matching engine
      worstFee: 0, // Will be filled by matching engine
      recipientId: subAccount() // Use the contract's subaccount ID as recipient
    });
    
    // Verify the trade
    _verifyOptionTrade(tradeData);
    
    // Decode option details from subId
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId);
    
    // Determine action type (0 = buy, 1 = sell)
    uint8 actionType = isBid ? 0 : 1;
    
    // Calculate premium and margin requirements
    (uint256 premium, uint256 marginRequired) = _calculateOptionPrice(expiry, strike, isCall, isBid);
    
    // Get current share price
    uint256 sharePrice = _getSharePrice();
    
    if (isBid) {
      // For buying to close a short position
      // Need to return margin to user
      uint256 marginAmount = (marginRequired * amount) / 1e18;
      uint256 marginShares = (marginAmount * 1e18) / sharePrice;
      
      // Check if user has enough shares for premium
      uint256 premiumAmount = (premium * amount) / 1e18;
      uint256 premiumShares = (premiumAmount * 1e18) / sharePrice;
      
      if ($.userShares[msg.sender] < premiumShares) {
        revert DTE_InsufficientShares();
      }
      
      // Deduct premium from user
      $.userShares[msg.sender] -= premiumShares;
      
      // Return margin to user
      $.userShares[msg.sender] += marginShares;
      
      // Update user position
      $.userOptionPositions[msg.sender][subId][actionType] += int256(amount);
      
      emit OptionPositionClosed(msg.sender, subId, amount, true, marginAmount);
    } else {
      // For selling to close a long position
      // Need to pay premium
      uint256 premiumAmount = (premium * amount) / 1e18;
      uint256 premiumShares = (premiumAmount * 1e18) / sharePrice;
      
      // Deduct premium from user
      $.userShares[msg.sender] -= premiumShares;
      
      // Update user position
      $.userOptionPositions[msg.sender][subId][actionType] -= int256(amount);
      
      emit OptionPositionClosed(msg.sender, subId, amount, false, premiumAmount);
    }
    
    // Store trade data in array
    $.pendingTrades.push(tradeData);
    $.pendingTradeCount++;
  }

  /**
   * @notice Calculate option price and margin requirements using Black76 model
   * @param expiry Expiry timestamp
   * @param strike Strike price
   * @param isCall Whether the option is a call
   * @param isLong Whether calculating price for a long position
   * @return premium The option premium in deposit asset decimals
   * @return marginRequired The margin required for the position in deposit asset decimals
   */
  function _calculateOptionPrice(
    uint expiry,
    uint strike,
    bool isCall,
    bool isLong
  ) internal view returns (uint256 premium, uint256 marginRequired) {
    DTETSAStorage storage $ = _getDTETSAStorage();
    
    // Get current spot price and volatility
    (uint spotPrice,) = $.baseFeed.getSpot();
    (uint vol, uint forwardPrice) = _getFeedValues(strike.toUint128(), expiry.toUint64());
    
    // Calculate time to expiry in seconds
    uint64 timeToExpiry = expiry > block.timestamp ? uint64(expiry - block.timestamp) : 0;
    
    // Calculate Black76 price for premium using the correct function
    (uint callPrice, uint putPrice) = Black76.prices(
      Black76.Black76Inputs({
        timeToExpirySec: timeToExpiry,
        volatility: vol.toUint128(),
        fwdPrice: forwardPrice.toUint128(),
        strikePrice: strike.toUint128(),
        discount: 1e18
      })
    );
    
    // Set premium based on option type
    premium = isCall ? callPrice : putPrice;
    
    // For short positions, we need to calculate margin requirements
    //@todo: need to verify this code again 
    // ignore as of now 
    if (!isLong) {
      if (isCall) {
        // For short calls, margin is the greater of:
        // 1. 20% of underlying + premium - out-of-the-money amount
        // 2. 10% of underlying + premium
        uint margin1 = (forwardPrice * 20 / 100) + premium;
        if (strike > forwardPrice) {
          margin1 -= strike - forwardPrice;
        }
        uint margin2 = (forwardPrice * 10 / 100) + premium;
        marginRequired = margin1 > margin2 ? margin1 : margin2;
      } else {
        // For short puts, margin is the greater of:
        // 1. 20% of underlying + premium - out-of-the-money amount
        // 2. 10% of strike price + premium
        uint margin1 = (forwardPrice * 20 / 100) + premium;
        if (strike < forwardPrice) {
          margin1 -= forwardPrice - strike;
        }
        uint margin2 = (strike * 10 / 100) + premium;
        marginRequired = margin1 > margin2 ? margin1 : margin2;
      }
    }
    
    // For long positions, only premium is required
    if (isLong) {
      marginRequired = premium;
    }
  }

  // /**
  //  * @notice Get the number of pending trades
  //  * @return The number of pending trades
  //  */
  // function getPendingTradeCount() public view returns (uint) {
  //   return _getDTETSAStorage().pendingTradeCount;
  // }
  
  // /**
  //  * @notice Get a pending trade by index
  //  * @param index The index of the trade to retrieve
  //  * @return The trade data
  //  */
  // function getPendingTrade(uint index) public view returns (ITradeModule.TradeData memory) {
  //   DTETSAStorage storage $ = _getDTETSAStorage();
  //   require(index < $.pendingTrades.length, "Index out of bounds");
  //   return $.pendingTrades[index];
  // }
  
  // /**
  //  * @notice Get all pending trades
  //  * @return An array of all pending trade data
  //  */
  // function getAllPendingTrades() public view returns (ITradeModule.TradeData[] memory) {
  //   DTETSAStorage storage $ = _getDTETSAStorage();
    
  //   // Create a new array with the same length as pendingTrades
  //   ITradeModule.TradeData[] memory trades = new ITradeModule.TradeData[]($.pendingTrades.length);
    
  //   // Copy all pending trades to the new array
  //   for (uint i = 0; i < $.pendingTrades.length; i++) {
  //     trades[i] = $.pendingTrades[i];
  //   }
    
  //   return trades;
  // }





  // Action Validation //

  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory /* extraData */ )
    internal
    virtual
    override
  {
    DTETSAStorage storage $ = _getDTETSAStorage();

    if (
      action.expiry < block.timestamp + $.dteParams.minSignatureExpiry
        || action.expiry > block.timestamp + $.dteParams.maxSignatureExpiry
    ) {
      revert DTE_InvalidActionExpiry();
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
      revert DTE_InvalidModule();
    }
  }


  // Withdrawals //


  function _verifyWithdrawAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    if (withdrawalData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert DTE_InvalidAsset();
    }

    (uint numShortCalls, uint numShortPuts, uint baseBalance, int cashBalance) = _getSubAccountStats();

    uint amount18 = ConvertDecimals.to18Decimals(withdrawalData.assetAmount, tsaAddresses.depositAsset.decimals());

    // For covered calls, we need to ensure we have enough collateral
    if (baseBalance < amount18 + numShortCalls) {
      revert DTE_WithdrawingUtilisedCollateral();
    }

    if (cashBalance < _getDTETSAStorage().dteParams.optionMaxNegCash) {
      revert DTE_WithdrawalNegativeCash();
    }
    
  }





  // Trading //
  

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    if (tradeData.desiredAmount <= 0) {
      revert DTE_InvalidDesiredAmount();
    }

    if (tradeData.asset == address(_getDTETSAStorage().optionAsset)) {
      _verifyOptionTrade(tradeData);
      // _updateTradeData(action); 
    } else {
      revert DTE_InvalidAsset();
    }
  }
  // function _updateTradeData(IMatching.Action memory action) internal {
  //   BaseTSAStorage storage $ = _getBaseTSAStorage();
  //   ITradeModule.TradeData memory actionTradeData = abi.decode(action.data, (ITradeModule.TradeData));

  //   for (uint i = 0; i < $.pendingTrades.length; i++) {
  //     ITradeModule.TradeData memory storedTrade = $.pendingTrades[i];
  //     // Check if this trade matches the action
  //     if (storedTrade.asset == action.asset &&
  //         storedTrade.subId == uint96(action.subId) &&
  //         storedTrade.isBid == action.isBid &&
  //         storedTrade.desiredAmount == action.amount) {
        
  //       // Handle removal based on position in array
  //       if ($.pendingTrades.length == 1) {
  //           // If this is the only element, just pop it
  //           $.pendingTrades.pop();
  //       } else if (i == $.pendingTrades.length - 1) {
  //           // If this is the last element, just pop it
  //           $.pendingTrades.pop();
  //       } else {
  //           // If this is not the last element, replace with last element and pop
  //           $.pendingTrades[i] = $.pendingTrades[$.pendingTrades.length - 1];
  //           $.pendingTrades.pop();
  //       }
  //       $.pendingTradeCount--;
  //       break;
  //     }
  //   }
  // }
  /**
   * @dev verifies option trades based on the type (call/put) and action (buy/sell)
   */
  function _verifyOptionTrade(ITradeModule.TradeData memory tradeData) internal view {
    (uint numShortCalls, uint numShortPuts, uint baseBalance, int cashBalance) = _getSubAccountStats();
    DTETSAStorage storage $ = _getDTETSAStorage();

    // Decode option details
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(tradeData.subId.toUint96());
    OptionType optionType = isCall ? OptionType.CALL : OptionType.PUT;
    OptionAction action = tradeData.isBid ? OptionAction.BUY : OptionAction.SELL;

    // Check if we have enough cash for buying options
    if (action == OptionAction.BUY && cashBalance < $.dteParams.optionMaxNegCash) {
      revert DTE_CannotBuyOptionsWithNegativeCash();
    }

    // For selling calls, check if we have enough collateral
    if (optionType == OptionType.CALL && action == OptionAction.SELL) {
      uint totalShortCalls = numShortCalls + tradeData.desiredAmount.abs();
      if (totalShortCalls > baseBalance * $.dteParams.maxOptionsToCollateralRatio / 1e18) {
        revert DTE_SellingTooManyCalls();
      }
    }

    // For selling puts, check if we have enough cash for potential assignment
    if (optionType == OptionType.PUT && action == OptionAction.SELL) {
      uint potentialAssignmentCost = strike * tradeData.desiredAmount.abs() / 1e18;
      if (potentialAssignmentCost > baseBalance) {
        revert DTE_SellingTooManyPuts();
      }
    }

    _verifyCollateralTradeFee(tradeData.worstFee, _getBasePrice());
    _validateOptionDetails(tradeData.subId.toUint96(), tradeData.limitPrice.toUint256(), optionType, action);
  }


  // Option Math //

  function _validateOptionDetails(uint96 subId, uint limitPrice, OptionType optionType, OptionAction action) internal view {
    DTETSAStorage storage $ = _getDTETSAStorage();

    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId);
    
    // Verify option type matches
    if ((isCall && optionType != OptionType.CALL) || (!isCall && optionType != OptionType.PUT)) {
      revert DTE_OptionTypeMismatch();
    }
    
    if (block.timestamp >= expiry) {
      revert DTE_OptionExpired();
    }
    
    uint timeToExpiry = expiry - block.timestamp;
    if (timeToExpiry < $.dteParams.optionMinTimeToExpiry || timeToExpiry > $.dteParams.optionMaxTimeToExpiry) {
      revert DTE_OptionExpiryOutOfBounds();
    }

    (uint vol, uint forwardPrice) = _getFeedValues(strike.toUint128(), expiry.toUint64());

    // Calculate option price and delta
    (uint callPrice, uint putPrice, uint Delta) = Black76.pricesAndDelta(
      Black76.Black76Inputs({
        timeToExpirySec: timeToExpiry.toUint64(),
        volatility: (vol.multiplyDecimal($.dteParams.optionVolSlippageFactor)).toUint128(),
        fwdPrice: forwardPrice.toUint128(),
        strikePrice: strike.toUint128(),
        discount: 1e18
      })
    );

    // For calls
    if (optionType == OptionType.CALL) {
      if (Delta > $.dteParams.optionMaxDelta) {
        revert DTE_OptionDeltaTooHigh();
      }

      if (action == OptionAction.SELL && limitPrice <= callPrice) {
        revert DTE_OptionPriceTooLow();
      }
      
      if (action == OptionAction.BUY && limitPrice >= callPrice) {
        revert DTE_OptionPriceTooHigh();
      }
    } 
    // For puts
    else {
      if (Delta > $.dteParams.optionMaxDelta) {
        revert DTE_OptionDeltaTooHigh();
      }

      if (action == OptionAction.SELL && limitPrice <= putPrice) {
        revert DTE_OptionPriceTooLow();
      }
      
      if (action == OptionAction.BUY && limitPrice >= putPrice) {
        revert DTE_OptionPriceTooHigh();
      }
    }
  }

  function _getFeedValues(uint128 strike, uint64 expiry) internal view returns (uint vol, uint forwardPrice) {
    DTETSAStorage storage $ = _getDTETSAStorage();

    StandardManager srm = StandardManager(address(getBaseTSAAddresses().manager));
    IStandardManager.AssetDetail memory assetDetails = srm.assetDetails($.optionAsset);
    (, IForwardFeed fwdFeed, IVolFeed volFeed) = srm.getMarketFeeds(assetDetails.marketId);
    (vol,) = volFeed.getVol(strike, expiry);
    (forwardPrice,) = fwdFeed.getForwardPrice(expiry);
  }

  // Account Value //


  /// @notice Get the number of short calls, short puts, base balance and cash balance of the subaccount
  function _getSubAccountStats() internal view returns (uint numShortCalls, uint numShortPuts, uint baseBalance, int cashBalance) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    ISubAccounts.AssetBalance[] memory balances = tsaAddresses.subAccounts.getAccountBalances(subAccount());
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == _getDTETSAStorage().optionAsset) {
        int balance = balances[i].balance;
        (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(uint96(balances[i].subId));
        
        if (isCall) {
          if (balance > 0) {
            // Long calls
            numShortCalls += 0;
          } else {
            // Short calls
            numShortCalls += balances[i].balance.abs();
          }
        } else {
          if (balance > 0) {
            // Long puts
            numShortPuts += 0;
          } else {
            // Short puts
            numShortPuts += balances[i].balance.abs();
          }
        }
      } else if (balances[i].asset == tsaAddresses.wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      } else if (balances[i].asset == tsaAddresses.cash) {
        cashBalance = balances[i].balance;
      }
    }
    return (numShortCalls, numShortPuts, baseBalance, cashBalance);
  }




  // Views //
 
  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }
  function _getBasePrice() internal view override returns (uint spotPrice) {
    (spotPrice,) = _getDTETSAStorage().baseFeed.getSpot();
  }

  function getSubAccountStats() public view returns (uint numShortCalls, uint numShortPuts, uint baseBalance, int cashBalance) {
    return _getSubAccountStats();
  }

  function getBasePrice() public view returns (uint) {
    return _getBasePrice();
  }

  function getDTETSAParams() public view returns (DTETSAParams memory) {
    return _getDTETSAStorage().dteParams;
  }

  function getCollateralManagementParams() public view returns (CollateralManagementParams memory) {
    return _getCollateralManagementParams();
  }

  function lastSeenHash() public view returns (bytes32) {
    return _getDTETSAStorage().lastSeenHash;
  }

  function getDTETSAAddresses()
    public
    view
    returns (ISpotFeed, IDepositModule, IWithdrawalModule, ITradeModule, IOptionAsset)
  {
    DTETSAStorage storage $ = _getDTETSAStorage();
    return ($.baseFeed, $.depositModule, $.withdrawalModule, $.tradeModule, $.optionAsset);
  }

  /**
   * @notice Get the number of shares a user has
   * @param user The user address
   * @return The number of shares
   */
  function getUserShares(address user) public view returns (uint) {
    return _getDTETSAStorage().userShares[user];
  }

  /**
   * @notice Get the value of a user's shares in deposit asset
   * @param user The user address
   * @return The value in deposit asset
   */
  function getUserShareValue(address user) public view returns (uint) {
    uint shares = getUserShares(user);
    return getSharesValue(shares);
  }




  // Events/Errors //
  event DTETSAParamsSet(DTETSAParams params);
  event OptionPositionOpened(address indexed user, uint96 indexed subId, uint256 amount, bool isBid, uint256 cost);
  event OptionPositionClosed(address indexed user, uint96 indexed subId, uint256 amount, bool isBid, uint256 proceeds);
  event TradeVerified(bytes32 indexed actionHash);

  error DTE_InvalidParams();
  error DTE_InvalidActionExpiry();
  error DTE_InvalidModule();
  error DTE_InvalidAsset();
  error DTE_DepositingTooMuch();
  error DTE_WithdrawingUtilisedCollateral();
  error DTE_WithdrawalNegativeCash();
  error DTE_SellingTooManyCalls();
  error DTE_SellingTooManyPuts();
  error DTE_CannotBuyOptionsWithNegativeCash();
  error DTE_OptionTypeMismatch();
  error DTE_OptionExpired();
  error DTE_OptionDeltaTooHigh();
  error DTE_OptionPriceTooLow();
  error DTE_OptionPriceTooHigh();
  error DTE_InvalidDesiredAmount();
  error DTE_OptionExpiryOutOfBounds();
  error DTE_InvalidOption();
  error DTE_InvalidAmount();
  error DTE_NoSessionKey();
  error DTE_InvalidOptionPosition();
  error DTE_InvalidExpiry();
  error DTE_InvalidStrike();
  error DTE_InsufficientBalance();
  error DTE_DepositBelowMinimum();
  error DTE_DepositCapExceeded();
  error DTE_MustReceiveShares();
  error DTE_InsufficientShares();

  
} 