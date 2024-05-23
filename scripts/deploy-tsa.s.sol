// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";
import "../src/periphery/LyraSettlementUtils.sol";
import {BaseOnChainSigningTSA} from "../src/tokenizedSubaccounts/BasicOnChainSigningTSA.sol";
import {BaseTSA} from "../src/tokenizedSubaccounts/BaseTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IMatching} from "../src/interfaces/IMatching.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";


contract DeploySettlementUtils is Utils {
  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    BaseOnChainSigningTSA tsa = new BasicOnChainSigningTSA(
      BaseTSA.BaseTSAInitParams({
        subAccounts: _getSubAccounts(),
        auction: _getAuctionAddress(),
        wrappedDepositAsset: _getBaseAddress("ETH"),
        manager: _getSRM(),
        matching: _getMatchingAddress(),
        symbol: "Tokenised DN WETH",
        name: "DNWETH"
      }),
      _getSpotFeed("ETH")
    );

    console2.log("TSA address: ", address(tsa));


    string memory objKey = "tsa-deployment";

    string memory finalObj = vm.serializeAddress(objKey, "DNWETH", address(tsa));

    // build path
    _writeToDeployments("tsa", finalObj);
  }

  function _getMatchingAddress() internal returns (IMatching) {
    return IMatching(abi.decode(vm.parseJson(_readDeploymentFile("matching"), ".matching"), (address)));
  }

  function _getBaseAddress(string memory marketName) internal returns (IWrappedERC20Asset) {
    return IWrappedERC20Asset(abi.decode(vm.parseJson(_readDeploymentFile(marketName), ".base"), (address)));
  }

  function _getSpotFeed(string memory marketName) internal returns (ISpotFeed) {
    return ISpotFeed(abi.decode(vm.parseJson(_readDeploymentFile(marketName), ".spotFeed"), (address)));
  }

  function _getSubAccounts() internal returns (ISubAccounts) {
    return ISubAccounts(abi.decode(vm.parseJson(_readDeploymentFile("core"), ".subAccounts"), (address)));
  }

  function _getSRM() internal returns (ILiquidatableManager) {
    return ILiquidatableManager(abi.decode(vm.parseJson(_readDeploymentFile("core"), ".srm"), (address)));
  }

  function _getAuctionAddress() internal returns (DutchAuction) {
    return DutchAuction(abi.decode(vm.parseJson(_readDeploymentFile("core"), ".auction"), (address)));
  }
}