// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

import "./BaseModule.sol";

contract TradeModule is BaseModule {
  struct TradeData {
    address asset;
    uint subId;
    // TODO: is using int here enough to cover perps use case?
    int worstPrice;
    int desiredAmount;
    uint recipientId; // todo cannot be 0 -> this account needs to be sent from matching
  } // todo short collat, transferred before ?

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
    uint perpDelta;
  }

  // @dev we fix the quoteAsset for the contracts so we can support eth/usdc etc as quoteAsset, but only one per
  //  deployment
  IAsset public immutable quoteAsset;

  IAsset public perpAsset;

  address feeSetter; // permissioned address for setting fee recipient
  uint feeRecipient;

  /// @dev we trust the nonce is unique for the given "VerifiedOrder" for the owner
  mapping(address owner => mapping(uint nonce => uint filled)) public filled;
  /// @dev in the case of recipient being 0, create new recipient and store the id here
  mapping(address owner => mapping(uint nonce => uint recipientId)) public recipientId;

  constructor(IAsset _quoteAsset, IAsset _perpAsset, address _feeSetter, uint _feeRecipient, Matching _matching) BaseModule(_matching) {
    quoteAsset = _quoteAsset;
    perpAsset = _perpAsset;
    feeSetter = _feeSetter;
    feeRecipient = _feeRecipient;
  }

  function setFeeRecipient(uint _feeRecipient) external onlyFeeSetter {
    feeRecipient = _feeRecipient;
  }
  
  function setPerpAsset(IAsset _perpAsset) external onlyFeeSetter {
    perpAsset = _perpAsset;
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
    int worstPrice = matchData.isBidder ? int(0) : type(int).max;

    console2.log("orders length", orders.length);
    for (uint i = 1; i < orders.length; i++) {
      FillDetails memory fillDetails = matchData.fillDetails[i - 1];

      OptionLimitOrder memory filledOrder = OptionLimitOrder({
        accountId: orders[i].accountId,
        owner: orders[i].owner,
        nonce: orders[i].nonce,
        data: abi.decode(orders[i].data, (TradeData)),
        perpDelta: 0
      });
      
      if (_isPerpTrade(filledOrder.data.asset)) {
        filledOrder.perpDelta = _calculatePerpDelta(fillDetails.price, fillDetails.amountFilled);
      }

      if (filledOrder.data.recipientId == 0) revert("Recipient Id canont be zero");
      if (filledOrder.accountId != fillDetails.filledAccount) revert("filled account does not match");
      // todo amountQuote need to change for perp
      console2.log("Fill limit order");
      _fillLimitOrder(filledOrder, fillDetails, !matchData.isBidder);
      console2.log("Fill limit order done");
      _addAssetTransfers(transferBatch, fillDetails, matchedOrder, filledOrder, matchData.isBidder, i * 3 - 3);
      console2.log("asset transfers done");

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

    console2.log("Transfer fee done ");
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

    accounts.submitTransfers(transferBatch, matchData.managerData);
    _returnAccounts(orders, newAccIds);
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
    console2.log("--- ADD ASSET TRANSFER ---");
    console2.log("isBidder", isBidder);
    console2.log("matchedOrder.accountId", matchedOrder.accountId);
    console2.log("matchedOrder.recipient", matchedOrder.data.recipientId);
    console2.log("filledOrder.accountId ", filledOrder.accountId);
    console2.log("filledOrder.recipient ", filledOrder.data.recipientId);
    console2.log("amount filled", isBidder ? int(fillDetails.amountFilled) : -int(fillDetails.amountFilled));
    int amtQuote = (int(fillDetails.amountFilled) * fillDetails.price / 1e18) + int(fillDetails.perpDelta); 

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

  // Difference between the perp Asset index price and the market price
  function _calculatePerpDelta(uint marketPrice, uint positionSize) internal pure returns (int delta) {
    int index = perpAsset.getIndexPriceSpot();
    delta = (marketPrice.toInt256() - index).multiplyDecimal(positionSize.toInt256());
  }

  function _isPerpTrade(address baseAsset) internal view returns (bool) {
    if (baseAsset == address(perpAsset)) return true;
    return false;
  }

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyFeeSetter() {
    require(msg.sender == feeSetter, "Only fee setter can call this");
    _;
  }
}
