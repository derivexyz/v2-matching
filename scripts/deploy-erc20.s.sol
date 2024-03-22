// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";
import "v2-core/src/assets/WrappedERC20Asset.sol";
import "v2-core/src/l2/LyraERC20.sol";


contract DeployBaseAsset is Utils {
  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    string memory name = vm.envString("TOKEN_NAME");
    string memory ticker = vm.envString("TICKER");
    uint8 decimals = uint8(vm.envUint("DECIMALS"));

    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("Deployer: ", deployer);
    LyraERC20 erc20 = new LyraERC20(name, ticker, 18);
    console2.log("ERC20 address: ", address(erc20));

    _writeToDeployments(string.concat("erc20-", ticker), string.concat("{\"erc20\": \"", vm.toString(address(erc20)), "\"}"));
  }
}