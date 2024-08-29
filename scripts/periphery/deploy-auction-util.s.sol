// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "../utils.sol";
import "../../src/periphery/LyraAuctionUtils.sol";

import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";


contract DeployAuctionUtil is Utils {
  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    string memory file = _readDeploymentFile("core");

    address subAccounts = abi.decode(vm.parseJson(file, ".subAccounts"), (address));
    address auctions = abi.decode(vm.parseJson(file, ".auction"), (address));
    address srm = abi.decode(vm.parseJson(file, ".srm"), (address));

    LyraAuctionUtils auctionUtils = new LyraAuctionUtils(ISubAccounts(subAccounts), DutchAuction(auctions), srm);

    console2.log("auction utils address: ", address(auctionUtils));
  }
}