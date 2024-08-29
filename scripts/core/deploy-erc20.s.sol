// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import "forge-std/StdJson.sol";
import {Utils} from "../utils.sol";
import "v2-core/src/assets/WrappedERC20Asset.sol";
import "v2-core/src/l2/LyraERC20.sol";


contract DeployBaseAsset is Utils {
  using stdJson for string;

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    string memory name = vm.envString("TOKEN_NAME");
    string memory ticker = vm.envString("TICKER");
    uint8 decimals = uint8(vm.envUint("DECIMALS"));

    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("Deployer: ", deployer);
    LyraERC20 erc20 = new LyraERC20(name, ticker, decimals);
    console2.log("ERC20 address: ", address(erc20));

    _appendToShared(_toLower(ticker), address(erc20));
  }

  function _appendToShared(string memory ticker, address erc20) internal {
    string memory shared = _readDeploymentFile("shared");
    string[] memory keys = vm.parseJsonKeys(shared, "$"); // ["key"]

    for (uint256 i = 0; i < keys.length; i++) {
      if (keccak256(abi.encodePacked(keys[i])) == keccak256("feedSigners")) {
        // abi.decode(vm.parseJson(file, ".feedSigners"), (address[]));
        address[] memory data = vm.parseJsonAddressArray(shared, ".feedSigners");
        vm.serializeAddress("sharedJson", "feedSigners", data);
        continue;
      } else {
        vm.serializeAddress("sharedJson", keys[i], vm.parseJsonAddress(shared, string.concat(".", keys[i])));
      }
    }

    string memory finalJson = vm.serializeAddress("sharedJson", ticker, erc20);
    _writeToDeployments("shared", finalJson);
  }
}