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
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IMatching} from "../src/interfaces/IMatching.sol";

import "forge-std/console2.sol";
import {Deployment, NetworkConfig} from "./types.sol";
import {Utils} from "./utils.sol";
import {RfqModule} from "../src/modules/RfqModule.sol";
import {LiquidateModule} from "../src/modules/LiquidateModule.sol";


contract DeployAll is Utils {

  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("Start deploying matching contract and modules! deployer: ", deployer);

    IMatching matching = _getMatchingAddress();

    RfqModule rfq = new RfqModule(matching, IAsset(_getCashAddress()), 1);
    LiquidateModule liquidate = new LiquidateModule(matching, _getAuctionAddress());
    
    Matching(address(matching)).setAllowedModule(address(rfq), true);
    Matching(address(matching)).setAllowedModule(address(liquidate), true);

    rfq.setPerpAsset(_getPerpAddress("ETH"), true);
    rfq.setPerpAsset(_getPerpAddress("BTC"), true);

    console2.log("rfq address: ", address(rfq));
    console2.log("liquidate address: ", address(liquidate));

    vm.stopBroadcast();
  }


  function _getMatchingAddress() internal returns (IMatching) {
    return IMatching(abi.decode(vm.parseJson(_readDeploymentFile("matching"), ".matching"), (address)));
  }

  /**
   * @dev write to deployments/{network}/core.json
   */
  function _getPerpAddress(string memory marketName) internal returns (IPerpAsset) {
    return IPerpAsset(abi.decode(vm.parseJson(_readDeploymentFile(marketName), ".perp"), (address)));
  }

  function _getCashAddress() internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile("core"), ".cash"), (address));
  }

  function _getAuctionAddress() internal returns (DutchAuction) {
    return DutchAuction(abi.decode(vm.parseJson(_readDeploymentFile("core"), ".auction"), (address)));
  }
}