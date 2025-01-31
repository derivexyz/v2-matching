// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;


import {Matching} from "../src/Matching.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import {LiquidateModule} from "../src/modules/LiquidateModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {RfqModule} from "../src/modules/RfqModule.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {PerpAsset} from "v2-core/src/assets/PerpAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";

import "forge-std/console2.sol";
import {Deployment, NetworkConfig} from "./types.sol";
import {Utils} from "./utils.sol";

/**
 * MARKET_NAME=TIA PRIVATE_KEY={} forge script scripts/add-perp-to-modules.s.sol --private-key {} --rpc-url {} --broadcast --priority-gas-price 1
 **/

// NOTE: only run on testnet

contract AddPerpToModules is Utils {

  /// @dev main functiond
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    TradeModule trade = TradeModule(__getTradeAddress());
    RfqModule rfq = RfqModule(__getRfqAddress());
    LiquidateModule liq = LiquidateModule(__getLiquidateAddress());

    console2.log("trade address: ", address(trade));

    string memory marketName = vm.envString("MARKET_NAME");

    address perp = __getPerpAddress(marketName);
    console2.log("perp address: ", perp);
    console2.log(trade.owner());

    trade.setPerpAsset(IPerpAsset(perp), true);
    rfq.setPerpAsset(IPerpAsset(perp), true);

    vm.stopBroadcast();
  }

  /**
   * @dev write to deployments/{network}/core.json
   */
  function __getTradeAddress() internal returns (address) {
    return abi.decode(vm.parseJson(_readMatchingDeploymentFile("matching"), ".trade"), (address));
  }

  function __getRfqAddress() internal returns (address) {
    return abi.decode(vm.parseJson(_readMatchingDeploymentFile("matching"), ".rfq"), (address));
  }

  function __getLiquidateAddress() internal returns (address) {
    return abi.decode(vm.parseJson(_readMatchingDeploymentFile("matching"), ".liquidate"), (address));
  }

  /**
   * @dev write to deployments/{network}/core.json
   */
  function __getPerpAddress(string memory marketName) internal returns (address) {
    return abi.decode(vm.parseJson(_readV2CoreDeploymentFile(marketName), ".perp"), (address));
  }
}