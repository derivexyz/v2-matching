import "forge-std/Script.sol";
import "forge-std/console.sol";

contract UtilBase is Script {
  constructor() {}

  function _getContract(string memory deploymentFile, string memory name) internal view returns (address) {
    return abi.decode(vm.parseJson(deploymentFile, string.concat(".", name)), (address));
  }

  function _getV2CoreAddressArray(string memory fileName, string memory name) internal view returns (address[] memory) {
    return abi.decode(_getV2CoreItemBytes(fileName, name), (address[]));
  }

  function _getV2CoreUint(string memory fileName, string memory name) internal view returns (uint256) {
    return abi.decode(_getV2CoreItemBytes(fileName, name), (uint256));
  }

  function _getV2CoreItemBytes(string memory fileName, string memory name) internal view returns (bytes memory) {
    return vm.parseJson(_readV2CoreDeploymentFile(fileName), string.concat(".", name));
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

  function _getV2CoreContract(string memory fileName, string memory name) internal view returns (address) {
    return _getContract(_readV2CoreDeploymentFile(fileName), name);
  }

  function _getMatchingContract(string memory fileName, string memory name) internal view returns (address) {
    return _getContract(_readMatchingDeploymentFile(fileName), name);
  }

  /// @dev use this function to write deployed contract address to deployments folder
  function _writeToDeployments(string memory filename, string memory content) internal {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(filename, ".json");
    vm.writeJson(content, string.concat(deploymentDir, chainDir, file));

    console.log("Written to deployment ", string.concat(deploymentDir, chainDir, file));
  }
}
