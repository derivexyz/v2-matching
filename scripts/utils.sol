// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {NetworkConfig} from "./types.sol";

contract Utils is Script {
  /// @dev get config from current chainId
  function _loadConfig() internal view returns (NetworkConfig memory config) {
    string memory file = _readV2CoreDeploymentFile("core");
    config.subAccounts = abi.decode(vm.parseJson(file, ".subAccounts"), (address));
    config.cash = abi.decode(vm.parseJson(file, ".cash"), (address));
    config.auction = abi.decode(vm.parseJson(file, ".auction"), (address));
    config.srm = abi.decode(vm.parseJson(file, ".srm"), (address));
  }

  /// @dev use this function to write deployed contract address to deployments folder
  function _writeToDeployments(string memory filename, string memory content) internal {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(filename, ".json");
    vm.writeJson(content, string.concat(deploymentDir, chainDir, file));

    console2.log("Written to deployment ", string.concat(deploymentDir, chainDir, file));
  }

  ///@dev read deployment file from deployments/
  function _readMatchingDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }

  function _readV2CoreDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/lib/v2-core/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }
}