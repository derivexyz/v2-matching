// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Matching} from "../src/Matching.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";
import {SubAccountCreator} from "../src/periphery/SubAccountCreator.sol";
import {LyraSettlementUtils} from "../src/periphery/LyraSettlementUtils.sol";
import {LyraAuctionUtils} from "../src/periphery/LyraAuctionUtils.sol";
import {RfqModule} from "../src/modules/RfqModule.sol";
import {LiquidateModule} from "../src/modules/LiquidateModule.sol";
import {AtomicSigningExecutor} from "../src/AtomicSigningExecutor.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";


struct NetworkConfig {
  address subAccounts;
  address cash;
  address srm;
  address auction;
}

struct Deployment {
  // matching contract
  Matching matching;
  // modules
  DepositModule deposit;
  TradeModule trade;
  TransferModule transfer;
  WithdrawalModule withdrawal;
  LiquidateModule liquidate;
  RfqModule rfq;
  // helper
  SubAccountCreator subAccountCreator;
  LyraSettlementUtils settlementUtil;
  LyraAuctionUtils auctionUtil;
  AtomicSigningExecutor atomicSigningExecutor;
  TSAShareHandler tsaShareHandler;
}