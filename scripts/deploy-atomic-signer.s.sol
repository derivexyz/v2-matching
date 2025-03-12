// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;


import "./shared/Utils.sol";
import "forge-std/console.sol";
import {AtomicSigningExecutor} from "../src/AtomicSigningExecutor.sol";
import {Deployment, NetworkConfig} from "./types.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {LiquidateModule} from "../src/modules/LiquidateModule.sol";
import {LyraAuctionUtils} from "../src/periphery/LyraAuctionUtils.sol";
import {LyraSettlementUtils} from "../src/periphery/LyraSettlementUtils.sol";
import {Matching} from "../src/Matching.sol";
import {RfqModule} from "../src/modules/RfqModule.sol";
import {SubAccountCreator} from "../src/periphery/SubAccountCreator.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";

import {TradeModule} from "../src/modules/TradeModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {Utils} from "./utils.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";


contract DeployAtomicSigner is UtilBase {

  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console.log("Start deploying matching contract and modules! deployer: ", deployer);

    _deployContract();

    vm.stopBroadcast();
  }


  /// @dev deploy and initiate contracts
  function _deployContract() internal {
    Matching matching = Matching(_getMatchingContract("matching", "matching"));

    AtomicSigningExecutor atomicSigningExecutor = new AtomicSigningExecutor(matching);

    if (block.chainid != 957) {
      matching.setTradeExecutor(address(atomicSigningExecutor), true);
    } else {
      console.log("Must set trade executor manually on Derive mainnet");
    }

    console.log("AtomicSigningExecutor deployed at: ", address(atomicSigningExecutor));
  }
}