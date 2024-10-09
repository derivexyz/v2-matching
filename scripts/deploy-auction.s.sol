// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";
import "../src/periphery/LyraSettlementUtils.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {ISecurityModule} from "v2-core/src/interfaces/ISecurityModule.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {IMatching} from "../src/interfaces/IMatching.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {LyraAuctionUtils} from "../src/periphery/LyraAuctionUtils.sol";
import {LiquidateModule} from "../src/modules/LiquidateModule.sol";
import {Matching} from "../src/Matching.sol";

import {BaseManager} from "v2-core/src/risk-managers/BaseManager.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {SecurityModule} from "v2-core/src/SecurityModule.sol";

contract DeployNewAuction is Utils {
  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    string memory file = _readV2CoreDeploymentFile("core");
    ISubAccounts subAccounts = ISubAccounts(abi.decode(vm.parseJson(file, ".subAccounts"), (address)));
    ISecurityModule securityModule = ISecurityModule(abi.decode(vm.parseJson(file, ".securityModule"), (address)));
    ICashAsset cash = ICashAsset(abi.decode(vm.parseJson(file, ".cash"), (address)));
    address srm = abi.decode(vm.parseJson(file, ".srm"), (address));

    address ethPMRM = abi.decode(vm.parseJson(_readV2CoreDeploymentFile("ETH"), ".pmrm"), (address));
    address btcPMRM = abi.decode(vm.parseJson(_readV2CoreDeploymentFile("BTC"), ".pmrm"), (address));
    IMatching matching = IMatching(abi.decode(vm.parseJson(_readMatchingDeploymentFile("matching"), ".matching"), (address)));


    DutchAuction auction = new DutchAuction(subAccounts, securityModule, cash);
    LyraAuctionUtils auctionUtils = new LyraAuctionUtils(subAccounts, auction, srm);

//    BaseManager(srm).setLiquidation(auction);
//    BaseManager(ethPMRM).setLiquidation(auction);
//    BaseManager(btcPMRM).setLiquidation(auction);

    auction.setWhitelistManager(srm, true);
    auction.setWhitelistManager(ethPMRM, true);
    auction.setWhitelistManager(btcPMRM, true);

//    CashAsset(address(cash)).setLiquidationModule(auction);

    LiquidateModule liquidateModule = new LiquidateModule(matching, auction);
//    Matching(address(matching)).setAllowedModule(address(liquidateModule), true);

    // TODO: securityModule.setWhitelistModule(old, false)
//    SecurityModule(address(securityModule)).setWhitelistModule(address(auction), true);

    console2.log("auction address: ", address(auction));
    console2.log("auction utils address: ", address(auctionUtils));
    console2.log("liquidate module address: ", address(liquidateModule));
  }
}