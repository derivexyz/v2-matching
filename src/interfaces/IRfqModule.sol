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
    int markPrice;
    int amount;
  }

  struct OrderData {
    uint makerAccount;
    uint makerFee;
    uint takerAccount;
    uint takerFee;
    bytes managerData;
  }

  error RFQM_InvalidActionsLength();
  error RFQM_InvalidSubaccountId();
  error RFQM_SignedAccountMismatch();
  error RFQM_InvalidTakerHash();
  error RFQM_FeeTooHigh();

  event OrderMatched(address base, uint taker, uint maker, bool takerIsBid, int amtQuote, uint amtBase);
  event FeeCharged(uint acc, uint recipient, uint takerFee);
}
