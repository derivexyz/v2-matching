// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Libraries
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";

// Interfaces
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {IDataReceiver} from "v2-core/src/interfaces/IDataReceiver.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IMatching} from "../interfaces/IMatching.sol";

/**
 * @title TradeModule
 * @dev Exchange assets between accounts based on signed limit orders (signed actions)
 */
contract TradeModule is ITradeModule, BaseModule {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  // @dev we fix the quoteAsset for the contracts so we only support one quoteAsset per deployment
  IAsset public immutable quoteAsset;

  mapping(IPerpAsset => bool) public isPerpAsset;

  uint public feeRecipient;

  /// @dev we trust the nonce is unique for the given "VerifiedAction" for the owner
  mapping(address owner => mapping(uint nonce => uint filled)) public filled;

  /// @dev we want to make sure once submitted with one nonce, we cant submit a different order with the same nonce
  /// note: it is still possible to submit different actions, but all parameters will match (but expiry may be different)
  mapping(address owner => mapping(uint nonce => bytes32 hash)) public seenNonces;

  constructor(IMatching _matching, IAsset _quoteAsset, uint _feeRecipient) BaseModule(_matching) {
    quoteAsset = _quoteAsset;
    feeRecipient = _feeRecipient;
  }

  ////////////////////
  //   Owner-Only   //
  ////////////////////

  /**
   * @dev set fee recipient account
   */
  function setFeeRecipient(uint _feeRecipient) external onlyOwner {
    feeRecipient = _feeRecipient;
  }

  /**
   * @dev set perp asset mapping
   */
  function setPerpAsset(IPerpAsset _perpAsset, bool isPerp) external onlyOwner {
    isPerpAsset[_perpAsset] = isPerp;
  }

  ////////////////////////
  //   Action Handler   //
  ////////////////////////

  /**
   * @dev Assumes VerifiedActions are sorted in the order: [takerAction, ...makerActions]
   * @param actions The actions to execute
   * @param actionDataBytes The data to pass to the module by the executor. Expected to be OrderData
   */
  function executeAction(VerifiedAction[] memory actions, bytes memory actionDataBytes)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length <= 1) revert TM_InvalidActionsLength();

    _checkOrderNonce(actions[0]);

    OrderData memory order = abi.decode(actionDataBytes, (OrderData));

    OptionLimitOrder memory takerOrder = OptionLimitOrder({
      subaccountId: actions[0].subaccountId,
      owner: actions[0].owner,
      nonce: actions[0].nonce,
      data: abi.decode(actions[0].data, (TradeData))
    });

    if (takerOrder.subaccountId != order.takerAccount) revert TM_SignedAccountMismatch();

    // Update feeds in advance, so perpPrice is up to date before we use it for the trade
    _processManagerData(order.managerData);

    // We can prepare the transfers as we iterate over the data
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](actions.length * 3 - 2);

    uint totalFilled;
    int limitPriceForTaker = takerOrder.data.isBid ? int(0) : type(int).max;

    // Iterate over maker accounts and fill their limit actions
    for (uint i = 1; i < actions.length; i++) {
      _checkOrderNonce(actions[i]);

      FillDetails memory fillDetails = order.fillDetails[i - 1];

      OptionLimitOrder memory makerOrder = OptionLimitOrder({
        subaccountId: actions[i].subaccountId,
        owner: actions[i].owner,
        nonce: actions[i].nonce,
        data: abi.decode(actions[i].data, (TradeData))
      });

      _verifyFilledAccount(makerOrder, fillDetails.filledAccount);

      if (makerOrder.data.isBid == takerOrder.data.isBid) revert TM_IsBidMismatch();
      if (makerOrder.data.asset != takerOrder.data.asset) revert TM_AssetMismatch();
      if (makerOrder.data.subId != takerOrder.data.subId) revert TM_AssetSubIdMismatch();

      _fillLimitOrder(makerOrder, fillDetails);

      // Attach transfer details to the execution batch
      _addAssetTransfers(transferBatch, fillDetails, takerOrder, makerOrder, (i - 1) * 3);

      totalFilled += fillDetails.amountFilled;
      if (takerOrder.data.isBid) {
        if (fillDetails.price > limitPriceForTaker) limitPriceForTaker = fillDetails.price;
      } else {
        if (fillDetails.price < limitPriceForTaker) limitPriceForTaker = fillDetails.price;
      }
    }

    transferBatch[transferBatch.length - 1] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: int(order.takerFee),
      fromAcc: takerOrder.subaccountId,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });

    emit FeeCharged(takerOrder.subaccountId, feeRecipient, order.takerFee);

    // Update filled amount for maker
    _fillLimitOrder(
      takerOrder,
      FillDetails({
        filledAccount: takerOrder.subaccountId,
        amountFilled: totalFilled,
        price: limitPriceForTaker,
        fee: order.takerFee
      })
    );

    // Execute all trades
    subAccounts.submitTransfers(transferBatch, order.managerData);

    // Return SubAccounts
    _returnAccounts(actions, newAccIds);

    return (newAccIds, newAccOwners);
  }

  function _verifyFilledAccount(OptionLimitOrder memory order, uint filledAccount) internal view {
    if (order.data.recipientId == 0) revert TM_InvalidRecipientId();
    if (order.subaccountId != filledAccount) revert TM_SignedAccountMismatch();
    // If the recipient isn't the signed account, verify the owner matches
    if (
      order.data.recipientId != order.subaccountId && matching.subAccountToOwner(order.data.recipientId) != order.owner
    ) {
      revert TM_InvalidRecipientId();
    }
  }

  /**
   * @dev Verify that the price and fee are within the limit order's bounds and update the filled amount.
   */
  function _fillLimitOrder(OptionLimitOrder memory order, FillDetails memory fill) internal {
    int finalPrice = fill.price;

    if (fill.fee.divideDecimal(fill.amountFilled) > order.data.worstFee) revert TM_FeeTooHigh();

    if (order.data.isBid) {
      if (finalPrice > order.data.limitPrice) revert TM_PriceTooHigh();
    } else {
      if (finalPrice < order.data.limitPrice) revert TM_PriceTooLow();
    }
    filled[order.owner][order.nonce] += fill.amountFilled;
    if (filled[order.owner][order.nonce] > uint(order.data.desiredAmount)) revert TM_FillLimitCrossed();
  }

  /**
   * @dev Add quote, base and fee transfers to the batch
   * @param matchedOrder The order by the taker. Matched against bunch of makers' orders.
   * @param filledOrder The order by the maker, that were filled.
   */
  function _addAssetTransfers(
    ISubAccounts.AssetTransfer[] memory transferBatch,
    FillDetails memory fillDetails,
    OptionLimitOrder memory matchedOrder,
    OptionLimitOrder memory filledOrder,
    uint startIndex
  ) internal {
    int amtQuote;
    if (_isPerp(matchedOrder.data.asset)) {
      int perpDelta = _getPerpDelta(matchedOrder.data.asset, fillDetails.price);
      amtQuote = perpDelta.multiplyDecimal(int(fillDetails.amountFilled));
    } else {
      amtQuote = fillDetails.price.multiplyDecimal(int(fillDetails.amountFilled));
    }

    bool isBidder = matchedOrder.data.isBid;

    transferBatch[startIndex] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      // if the matched trader is the bidder, they are paying the quote asset, otherwise they are receiving it
      amount: isBidder ? amtQuote : -amtQuote,
      fromAcc: isBidder ? matchedOrder.subaccountId : matchedOrder.data.recipientId,
      toAcc: isBidder ? filledOrder.data.recipientId : filledOrder.subaccountId,
      assetData: bytes32(0)
    });

    transferBatch[startIndex + 1] = ISubAccounts.AssetTransfer({
      asset: IAsset(matchedOrder.data.asset),
      subId: matchedOrder.data.subId,
      amount: isBidder ? int(fillDetails.amountFilled) : -int(fillDetails.amountFilled),
      fromAcc: isBidder ? filledOrder.subaccountId : filledOrder.data.recipientId,
      toAcc: isBidder ? matchedOrder.data.recipientId : matchedOrder.subaccountId,
      assetData: bytes32(0)
    });

    transferBatch[startIndex + 2] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: int(fillDetails.fee),
      fromAcc: filledOrder.subaccountId,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });

    emit OrderMatched(
      matchedOrder.data.asset,
      matchedOrder.subaccountId,
      filledOrder.subaccountId,
      isBidder,
      amtQuote,
      fillDetails.amountFilled
    );

    emit FeeCharged(filledOrder.subaccountId, feeRecipient, fillDetails.fee);
  }

  /**
   * @dev Send data to IDataReceiver contracts. Can be used to update oracles before pairing trades
   */
  function _processManagerData(bytes memory managerData) internal {
    if (managerData.length == 0) return;
    IBaseManager.ManagerData[] memory managerDatas = abi.decode(managerData, (IBaseManager.ManagerData[]));
    for (uint i; i < managerDatas.length; i++) {
      IDataReceiver(managerDatas[i].receiver).acceptData(managerDatas[i].data);
    }
  }

  function _isPerp(address baseAsset) internal view returns (bool) {
    return isPerpAsset[IPerpAsset(baseAsset)];
  }

  /**
   * @dev Get the difference between the perp price and the traded price
   *      If perp price is $2000, and the limit order matched is trading at $2005, the delta is $5
   *      The bidder (long) needs to pay $5 per Perp contract traded
   */
  function _getPerpDelta(address perpAsset, int marketPrice) internal view returns (int delta) {
    (uint perpPrice,) = IPerpAsset(perpAsset).getPerpPrice();
    return (marketPrice - perpPrice.toInt256());
  }

  function _checkOrderNonce(VerifiedAction memory order) internal {
    bytes32 storedHash = seenNonces[order.owner][order.nonce];
    if (storedHash == bytes32(0)) {
      seenNonces[order.owner][order.nonce] = keccak256(order.data);
    } else if (storedHash != keccak256(order.data)) {
      revert TM_InvalidNonce();
    }
  }
}
