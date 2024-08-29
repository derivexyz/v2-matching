// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;


import {SubAccounts} from "v2-core/src/SubAccounts.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {OptionAsset} from "v2-core/src/assets/OptionAsset.sol";
import {PerpAsset} from "v2-core/src/assets/PerpAsset.sol";
import {WrappedERC20Asset} from "v2-core/src/assets/WrappedERC20Asset.sol";
import {InterestRateModel} from "v2-core/src/assets/InterestRateModel.sol";
import {SecurityModule} from "v2-core/src/SecurityModule.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {LyraSpotFeed} from "v2-core/src/feeds/LyraSpotFeed.sol";
import {LyraSpotDiffFeed} from "v2-core/src/feeds/LyraSpotDiffFeed.sol";
import {LyraVolFeed} from "v2-core/src/feeds/LyraVolFeed.sol";
import {LyraRateFeedStatic} from "v2-core/src/feeds/static/LyraRateFeedStatic.sol";
import {LyraForwardFeed} from "v2-core/src/feeds/LyraForwardFeed.sol";

// Standard Manager (SRM)
import {StandardManager} from "v2-core/src/risk-managers/StandardManager.sol";
import {SRMPortfolioViewer} from "v2-core/src/risk-managers/SRMPortfolioViewer.sol";

// Portfolio Manager (PMRM)
import {PMRM} from "v2-core/src/risk-managers/PMRM.sol";
import {PMRMLib} from "v2-core/src/risk-managers/PMRMLib.sol";
import {BasePortfolioViewer} from "v2-core/src/risk-managers/BasePortfolioViewer.sol";

// Periphery Contracts
import {OracleDataSubmitter} from "v2-core/src/periphery/OracleDataSubmitter.sol";
import {OptionSettlementHelper} from "v2-core/src/periphery/OptionSettlementHelper.sol";
import {PerpSettlementHelper} from "v2-core/src/periphery/PerpSettlementHelper.sol";


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


struct NetworkConfig {
  address subAccounts;
  address cash;
  address srm;
  address auction;
}

struct ConfigJson {
  address usdc;
  address[] feedSigners;
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

  SubAccounts subAccounts;
  InterestRateModel rateModel;
  CashAsset cash;
  SecurityModule securityModule;
  DutchAuction auction;
  // standard risk manager: one for the whole system
  StandardManager srm;
  SRMPortfolioViewer srmViewer;

  ISpotFeed stableFeed;
  OracleDataSubmitter dataSubmitter;
  OptionSettlementHelper optionSettlementHelper;
  PerpSettlementHelper perpSettlementHelper;
}

struct Market {
  // lyra asset
  OptionAsset option;
  PerpAsset perp;
  WrappedERC20Asset base;
  // feeds
  LyraSpotFeed spotFeed;
  LyraSpotDiffFeed perpFeed;
  LyraSpotDiffFeed iapFeed;
  LyraSpotDiffFeed ibpFeed;
  LyraVolFeed volFeed;
  LyraRateFeedStatic rateFeed;
  LyraForwardFeed forwardFeed;
  // manager for specific market
  PMRM pmrm;
  PMRMLib pmrmLib;
  BasePortfolioViewer pmrmViewer;
}