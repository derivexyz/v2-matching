// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;


import {Matching} from "../src/Matching.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {LiquidateModule} from "../src/modules/LiquidateModule.sol";
import {RfqModule} from "../src/modules/RfqModule.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";
import {SubAccountCreator} from "../src/periphery/SubAccountCreator.sol";
import {LyraSettlementUtils} from "../src/periphery/LyraSettlementUtils.sol";
import {LyraAuctionUtils} from "../src/periphery/LyraAuctionUtils.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";
import {AtomicSigningExecutor} from "../src/AtomicSigningExecutor.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";

import "forge-std/console.sol";
import {Deployment, NetworkConfig} from "./types.sol";
import {Utils} from "./utils.sol";


contract DeployAtomicSigner is Utils {

  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console.log("Start deploying matching contract and modules! deployer: ", deployer);

    _deployAllContracts();

    vm.stopBroadcast();
  }


  /// @dev deploy and initiate contracts
  function _deployAllContracts() internal {
    uint defaultFeeRecipient = 1;

    Matching matching = Matching(0x3cc154e220c2197c5337b7Bd13363DD127Bc0C6E);

    AtomicSigningExecutor atomicSigningExecutor = new AtomicSigningExecutor(matching);

    matching.setTradeExecutor(address(atomicSigningExecutor), true);

    console.log("AtomicSigningExecutor deployed at: ", address(atomicSigningExecutor));
  }
}