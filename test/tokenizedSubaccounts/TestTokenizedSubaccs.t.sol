// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";
import "../../src/periphery/LyraAuctionUtils.sol";
import "../shared/MatchingBase.t.sol";
import {IntegrationTestBase} from "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";
import {DNLRTTSA} from "../../src/tokenizedSubaccounts/DNLRTTSA.sol";
import {BaseTSA} from "../../src/tokenizedSubaccounts/BaseTSA.sol";

contract TokenizedSubaccountsTest is IntegrationTestBase {
  DNLRTTSA public tokenizedSubacc;

  Matching public matching;
  DepositModule public depositModule;
  WithdrawalModule public withdrawalModule;
  TransferModule public transferModule;
  TradeModule public tradeModule;
  LiquidateModule public liquidateModule;
  RfqModule public rfqModule;

  function setUp() public {
    _setupIntegrationTestComplete();

    _deployMatching();

    //     ISubAccounts subAccounts;
    //    DutchAuction auction;
    //    IWrappedERC20Asset wrappedDepositAsset;
    //    ILiquidatableManager manager;
    //    IMatching matching;
    //    string symbol;
    //    string name;
    tokenizedSubacc = new DNLRTTSA(
      BaseTSA.BaseTSAInitParams({
        subAccounts: subAccounts,
        auction: auction,
        wrappedDepositAsset: markets["weth"].base,
        manager: srm,
        matching: matching,
        symbol: "Tokenised DN WETH",
        name: "Tokie DN WETH"
      }),
      markets["weth"].spotFeed
    );
  }


  function _deployMatching() internal {
    // Setup matching contract and modules
    matching = new Matching(subAccounts);
    depositModule = new DepositModule(matching);
    withdrawalModule = new WithdrawalModule(matching);
    transferModule = new TransferModule(matching);
    tradeModule = new TradeModule(matching, IAsset(address(cash)), aliceAcc);
    tradeModule.setPerpAsset(IPerpAsset(address(markets["weth"].perp)), true);
    liquidateModule = new LiquidateModule(matching, auction);
    rfqModule = new RfqModule(matching, IAsset(address(cash)), aliceAcc);
    rfqModule.setPerpAsset(IPerpAsset(address(markets["weth"].perp)), true);

    matching.setAllowedModule(address(depositModule), true);
    matching.setAllowedModule(address(withdrawalModule), true);
    matching.setAllowedModule(address(transferModule), true);
    matching.setAllowedModule(address(tradeModule), true);
    matching.setAllowedModule(address(liquidateModule), true);
    matching.setAllowedModule(address(rfqModule), true);

//    domainSeparator = matching.domainSeparator();
    matching.setTradeExecutor(address(this), true);

  }

  function testCanDepositTradeWithdraw() public {
    markets["weth"].erc20.mint(address(this), 1e18);
    markets["weth"].erc20.approve(address(tokenizedSubacc), 1e18);
    tokenizedSubacc.deposit(1e18);

    // Register a session key
//    tokenizedSubacc.registerSessionKey(address(this));

    // Trade
//    tokenizedSubacc.trade(1000e6, 1000e6, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    // Withdraw

  }

//
//  function _transferOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
//    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
//      fromAcc: fromAcc,
//      toAcc: toAcc,
//      asset: markets["weth"].option,
//      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
//      amount: amount,
//      assetData: ""
//    });
//    subAccounts.submitTransfer(transfer, "");
//  }
}
