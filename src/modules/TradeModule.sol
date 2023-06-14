// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import "openzeppelin/utils/Math/SignedMath.sol";

import "./BaseModule.sol";

contract TradeModule is BaseModule {
  struct TradeData {
    address asset;
    uint subId;
    // TODO: is using int here enough to cover perps use case?
    int worstPrice;
    int desiredAmount;
    uint recipientId; // if 0 -> spin up new account
  }

  struct OptionLimitOrder {
    uint accountId;
    address owner;
    uint nonce;
    TradeData data;
  }

  /**
   * @dev A "Fill" is a trade that occurs when a market is crossed. A single new order can result in multiple fills.
   * The matcher is the account that is crossing the market. The filledAccounts are those being filled.
   *
   * If the order is a bid;
   * the matcher is sending the filled accounts quoteAsset, and receiving the asset from the filled accounts.
   *
   * If the order is an ask;
   * the matcher is sending the filled accounts asset, and receiving the quoteAsset from the filled accounts.
   */

  struct MatchData {
    uint matchedAccount;
    bool isBidder;
    uint matcherFee;
    FillDetails[] fillDetails;
    bytes managerData;
  }

  struct FillDetails {
    uint filledAccount;
    uint amountFilled;
    // price per asset
    int price;
    // total fee for filler
    uint fee;
  }

  // @dev we fix the quoteAsset for the contracts so we can support eth/usdc etc as quoteAsset, but only one per
  //  deployment
  IAsset public immutable quoteAsset;
  uint feeRecipient; // TODO: setter

  /// @dev we trust the nonce is unique for the given "VerifiedOrder" for the owner
  mapping(address owner => mapping(uint nonce => uint filled)) public filled;
  /// @dev in the case of recipient being 0, create new recipient and store the id here
  mapping(address owner => mapping(uint nonce => uint recipientId)) public recipientId;

  constructor(IAsset _quoteAsset, uint _feeRecipient, Matching _matching) BaseModule(_matching) {
    quoteAsset = _quoteAsset;
    feeRecipient = _feeRecipient;
  }

  /// @dev Assumes VerifiedOrders are sorted in the order: [matchedAccount, ...filledAccounts]
  /// Also trusts nonces are never repeated for the same owner. If the same nonce is received, it is assumed to be the
  /// same order.
  function matchOrders(VerifiedOrder[] memory orders, bytes memory matchDataBytes)
    public
    returns (uint[] memory accountIds, address[] memory owners)
  {
    MatchData memory matchData = abi.decode(matchDataBytes, (MatchData));

    OptionLimitOrder memory matchedOrder = OptionLimitOrder({
      accountId: orders[0].accountId,
      owner: orders[0].owner,
      nonce: orders[0].nonce,
      data: abi.decode(orders[0].data, (TradeData))
    });

    if (matchedOrder.accountId != matchData.matchedAccount) revert("matched account does not match");

    // We can prepare the transfers as we iterate over the data
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](orders.length * 3 - 2);

    uint totalFilled;
    int worstPrice = matchData.isBidder ? int(0) : type(int).max;
    for (uint i = 1; i < orders.length; i++) {
      FillDetails memory fillDetails = matchData.fillDetails[i - 1];
      OptionLimitOrder memory filledOrder = OptionLimitOrder({
        accountId: orders[i].accountId,
        owner: orders[i].owner,
        nonce: orders[i].nonce,
        data: abi.decode(orders[i].data, (TradeData))
      });
      if (filledOrder.accountId != fillDetails.filledAccount) revert("filled account does not match");

      _fillLimitOrder(filledOrder, fillDetails, !matchData.isBidder);
      _addAssetTransfers(transferBatch, fillDetails, matchedOrder, filledOrder, matchData.isBidder, i * 3 - 3);

      totalFilled += fillDetails.amountFilled;
      if (matchData.isBidder) {
        if (fillDetails.price > worstPrice) worstPrice = fillDetails.price;
      } else {
        if (fillDetails.price < worstPrice) worstPrice = fillDetails.price;
      }
    }

    transferBatch[transferBatch.length - 1] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: int(matchData.matcherFee),
      fromAcc: matchedOrder.accountId,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });

    _fillLimitOrder(
      matchedOrder,
      FillDetails({
        filledAccount: matchedOrder.accountId,
        amountFilled: totalFilled,
        price: worstPrice,
        fee: matchData.matcherFee
      }),
      matchData.isBidder
    );

    // submitTransfers(transferBatch, matchData.managerData);
  }

  function _fillLimitOrder(OptionLimitOrder memory order, FillDetails memory fill, bool isBidder) internal {
    int finalPrice = fill.price + int(fill.fee * fill.amountFilled / SignedMath.abs(order.data.desiredAmount));
    if (isBidder) {
      if (finalPrice > order.data.worstPrice) revert("price too high");
    } else {
      if (finalPrice < order.data.worstPrice) revert("price too low");
    }
    filled[order.owner][order.nonce] += fill.amountFilled;
    if (filled[order.owner][order.nonce] > uint(order.data.desiredAmount)) revert("too much filled");
  }

  function _addAssetTransfers(
    ISubAccounts.AssetTransfer[] memory transferBatch,
    FillDetails memory fillDetails,
    OptionLimitOrder memory matchedOrder,
    OptionLimitOrder memory filledOrder,
    bool isBidder,
    uint startIndex
  ) internal view {
    int amtQuote = int(fillDetails.amountFilled) * fillDetails.price / 1e18;

    transferBatch[startIndex] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      // if the matched trader is the bidder, they are paying the quote asset, otherwise they are receiving it
      amount: isBidder ? amtQuote : -amtQuote,
      fromAcc: isBidder ? matchedOrder.accountId : matchedOrder.data.recipientId,
      toAcc: isBidder ? filledOrder.data.recipientId : filledOrder.accountId,
      assetData: bytes32(0)
    });

    transferBatch[startIndex + 1] = ISubAccounts.AssetTransfer({
      asset: IAsset(matchedOrder.data.asset),
      subId: matchedOrder.data.subId,
      amount: isBidder ? int(fillDetails.amountFilled) : -int(fillDetails.amountFilled),
      fromAcc: isBidder ? matchedOrder.data.recipientId : matchedOrder.accountId,
      toAcc: isBidder ? filledOrder.accountId : filledOrder.data.recipientId,
      assetData: bytes32(0)
    });

    transferBatch[startIndex + 2] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: int(fillDetails.fee),
      fromAcc: filledOrder.accountId,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });
  }
}
