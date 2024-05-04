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

contract TokenizedSubaccountsTest is IntegrationTestBase, MatchingHelpers {
  DNLRTTSA public tokenizedSubacc;

  function setUp() public {
    _setupIntegrationTestComplete();

    MatchingHelpers._deployMatching(subAccounts, address(cash), auction, 0);

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

}
