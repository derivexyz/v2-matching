// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";


interface ITradeModule is IBaseModule {
  struct OptionLimitOrder {
    uint accountId;
    address owner;
    uint nonce;
    TradeData data;
  }

  struct TradeData {
    address asset;
    uint subId;
    int worstPrice;
    int desiredAmount;
    // Fee per asset traded
    uint worstFee;
    uint recipientId;
    bool isBid;
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

  struct ActionData {
    uint matchedAccount;
    // total fee for matcher
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

  function quoteAsset() external view returns (IAsset);
  function isPerpAsset(IPerpAsset perpAsset) external view returns (bool);
  function feeRecipient() external view returns (uint);
  function filled(address owner, uint nonce) external view returns (uint);
  function seenNonces(address owner, uint nonce) external view returns (bytes32);
  function setFeeRecipient(uint _feeRecipient) external;
  function setPerpAsset(IPerpAsset _perpAsset, bool isPerp) external;


  error TM_InvalidOrdersLength();
  error TM_SignedAccountMismatch();
  error TM_IsBidMismatch();
  error TM_InvalidRecipientId();
  error TM_InvalidNonce();
}
