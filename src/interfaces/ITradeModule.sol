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
    int limitPrice;
    int desiredAmount;
    // Fee per asset traded
    uint worstFee;
    uint recipientId;
    bool isBid;
  }

  /**
   * @dev A "Fill" is a trade that occurs when a market is crossed. A single new order can result in multiple fills.
   * The taker is the account that is crossing the market. The makerAccounts are those with orders being filled.
   *
   * If the taker order is a bid;
   * the taker is sending the maker accounts quoteAsset, and receiving the baseAsset from the maker accounts.
   *
   * If the taker order is an ask;
   * the taker is sending the maker accounts baseAsset, and receiving the quoteAsset from the maker accounts.
   */

  struct ActionData {
    uint takerAccount;
    // total fee for taker
    uint takerFee;
    // maker details
    FillDetails[] fillDetails;
    bytes managerData;
  }

  struct FillDetails {
    uint filledAccount;
    uint amountFilled;
    // price per asset
    int price;
    // total fee for maker
    uint fee;
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
  error TM_FeeTooHigh();
  error TM_PriceTooHigh();
  error TM_PriceTooLow();
  error TM_FillLimitCrossed();
}
