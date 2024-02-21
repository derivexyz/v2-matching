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

    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

//    string memory file = _readDeploymentFile("core");

//    address subAccounts = abi.decode(vm.parseJson(file, ".subAccounts"), (address));

    // constructor(ISubAccounts _subAccounts, IERC20Metadata _wrappedAsset)
    LyraERC20 erc20 = new LyraERC20("Synthetix Network Token", "SNX", 18);
//    WrappedERC20Asset wrappedERC20Asset = new WrappedERC20Asset(ISubAccounts(subAccounts), IERC20Metadata(erc20Address));

    console2.log("ERC20 address: ", address(erc20));
//    console2.log("WrappedERC20Asset: ", address(wrappedERC20Asset));
  }
}