// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";

interface IRfqModule is IBaseModule {
  struct RfqOrder {
    uint maxFee;
    TradeData[] trades;
  }

  struct TakerOrder {
    /// @dev a hash of the RfqOrder being traded against
    bytes32 orderHash;
    uint maxFee;
  }

  struct TradeData {
    address asset;
    uint subId;
    /// @dev The mark price for the asset traded. Always positive.
    /// e.g. If opening a short, this will be paid to the seller/taken from the buyer
    uint price;
    int amount;
  }

  struct FillData {
    uint makerAccount;
    uint makerFee;
    uint takerAccount;
    uint takerFee;
    bytes managerData;
  }

  struct MatchedOrderData {
    address asset;
    uint subId;
    /// @dev Includes the perp price difference
    int quoteAmt;
    int baseAmt;
  }

  event RFQTradeCompleted(uint indexed maker, uint indexed taker, MatchedOrderData[] trades);
  event FeeCharged(uint acc, uint recipient, uint takerFee);

  error RFQM_InvalidActionsLength();
  error RFQM_InvalidSubaccountId();
  error RFQM_SignedAccountMismatch();
  error RFQM_InvalidTakerHash();
  error RFQM_FeeTooHigh();
}
