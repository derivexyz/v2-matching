// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract ForkBase is Test {
  constructor() {}

  modifier skipped() {
    vm.skip(true);
    _;
  }

  function _getContract(string memory deploymentFile, string memory name) internal view returns (address) {
    return abi.decode(vm.parseJson(deploymentFile, string.concat(".", name)), (address));
  }

  ///@dev read deployment file from deployments/
  function _readV2CoreDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/lib/v2-core/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }

  ///@dev read deployment file from deployments/
  function _readMatchingDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }
}
