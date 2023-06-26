// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";

import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

import {BaseModule} from "./BaseModule.sol";
import {Matching} from "../Matching.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

contract TradeModule is BaseModule, Ownable2Step {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  struct TradeData {
    address asset;
    uint subId;
    int worstPrice;
    int desiredAmount;
    uint worstFee;
    uint recipientId;
    bool isBid;
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
    // for perp trades, the difference in the fill price and the perp price
    // users will only transfer this amount for a perp trade
    int perpDelta;
  }

  // @dev we fix the quoteAsset for the contracts so we can support eth/usdc etc as quoteAsset, but only one per
  //  deployment
  IAsset public immutable quoteAsset;

  mapping(IPerpAsset => bool) public perpAssets;

  uint public feeRecipient;

  /// @dev we trust the nonce is unique for the given "VerifiedOrder" for the owner
  mapping(address owner => mapping(uint nonce => uint filled)) public filled;
  /// @dev in the case of recipient being 0, create new recipient and store the id here
  mapping(address owner => mapping(uint nonce => uint recipientId)) public recipientId;

  constructor(Matching _matching, IAsset _quoteAsset, uint _feeRecipient) BaseModule(_matching) Ownable2Step() {
    quoteAsset = _quoteAsset;
    feeRecipient = _feeRecipient;
  }

  function setFeeRecipient(uint _feeRecipient) external onlyOwner {
    feeRecipient = _feeRecipient;
  }

  function setPerpAsset(IPerpAsset _perpAsset, bool isPerp) external onlyOwner {
    perpAssets[_perpAsset] = isPerp;
  }

  /// @dev Assumes VerifiedOrders are sorted in the order: [matchedAccount, ...filledAccounts]
  /// Also trusts nonces are never repeated for the same owner. If the same nonce is received, it is assumed to be the
  /// same order.
  function matchOrders(VerifiedOrder[] memory orders, bytes memory matchDataBytes)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
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
    int worstPrice = matchedOrder.data.isBid ? int(0) : type(int).max;

    for (uint i = 1; i < orders.length; i++) {
      FillDetails memory fillDetails = matchData.fillDetails[i - 1];

      OptionLimitOrder memory filledOrder = OptionLimitOrder({
        accountId: orders[i].accountId,
        owner: orders[i].owner,
        nonce: orders[i].nonce,
        data: abi.decode(orders[i].data, (TradeData))
      });

      if (filledOrder.data.recipientId == 0) revert("Recipient Id canont be zero");
      if (filledOrder.accountId != fillDetails.filledAccount) revert("filled account does not match");
      if (filledOrder.data.isBid == matchedOrder.data.isBid) revert("isBid mismatch");

      _fillLimitOrder(filledOrder, fillDetails);
      _addAssetTransfers(transferBatch, fillDetails, matchedOrder, filledOrder, i * 3 - 3);

      totalFilled += fillDetails.amountFilled;
      if (matchedOrder.data.isBid) {
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
        fee: matchData.matcherFee,
        perpDelta: 0
      })
    );

    accounts.submitTransfers(transferBatch, matchData.managerData);
    _returnAccounts(orders, newAccIds);
  }

  function _fillLimitOrder(OptionLimitOrder memory order, FillDetails memory fill) internal {
    int finalPrice = fill.price;

    if (fill.fee > order.data.worstFee) revert("fee too high");

    if (order.data.isBid) {
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
    uint startIndex
  ) internal view {
    int amtQuote;
    if (_isPerp(matchedOrder.data.asset)) {
      int perpDelta = _getPerpDelta(matchedOrder.data.asset, fillDetails.price);
      amtQuote = perpDelta.multiplyDecimal(int(fillDetails.amountFilled));
      console2.log("perpDelta", perpDelta);
      console2.log("fillDetails.price", fillDetails.price);
    } else {
      amtQuote = fillDetails.price.multiplyDecimal(int(fillDetails.amountFilled));
    }

    bool isBidder = matchedOrder.data.isBid;

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
      fromAcc: isBidder ? filledOrder.accountId : filledOrder.data.recipientId,
      toAcc: isBidder ? matchedOrder.data.recipientId : matchedOrder.accountId,
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

  function _isPerp(address baseAsset) internal view returns (bool) {
    return perpAssets[IPerpAsset(baseAsset)];
  }

  // Difference between the perp price and the traded price
  function _getPerpDelta(address perpAsset, int marketPrice) internal view returns (int delta) {
    (uint perpPrice,) = IPerpAsset(perpAsset).getPerpPrice();
    return (marketPrice - perpPrice.toInt256());
  }
}
