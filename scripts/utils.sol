// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {NetworkConfig} from "./types.sol";

contract Utils is Script {
  /// @dev get config from current chainId
  function _loadConfig() internal view returns (NetworkConfig memory config) {
    string memory file = _readDeploymentFile("core");
    config.subAccounts = abi.decode(vm.parseJson(file, ".subAccounts"), (address));
    config.cash = abi.decode(vm.parseJson(file, ".cash"), (address));
    config.auction = abi.decode(vm.parseJson(file, ".auction"), (address));
    config.srm = abi.decode(vm.parseJson(file, ".srm"), (address));
  }

  ///@dev read input from json 
  ///@dev standard path: scripts/input/{chainId}/{input}.json, as defined in 
  ////    https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts
  function _readInput(string memory input) internal view returns (string memory) {
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(input, ".json");
    return vm.readFile(string.concat(inputDir, chainDir, file));
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
  function _readDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }
}