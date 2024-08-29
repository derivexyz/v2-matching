// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;


import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {PerpAsset} from "v2-core/src/assets/PerpAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {LyraRateFeedStatic} from "v2-core/src/feeds/static/LyraRateFeedStatic.sol";

import {WrappedERC20Asset} from "v2-core/src/assets/WrappedERC20Asset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {BaseManager} from "v2-core/src/risk-managers/BaseManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";

import {LyraERC20} from "v2-core/src/l2/LyraERC20.sol";

import "forge-std/console2.sol";
import {Deployment, NetworkConfig} from "../types.sol";
import {Utils} from "../utils.sol";


/// @dev For local dev only
contract UpdateCallees is Utils {

  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    string memory shared = _readDeploymentFile("shared");
    string memory core = _readDeploymentFile("core");
    string memory ethMarket = _readDeploymentFile("ETH");
    string memory btcMarket = _readDeploymentFile("BTC");
    string memory snxMarket = _readDeploymentFile("SNX");

    // USDC

    _addWhitelistedCallee(_getContractAddr(core, "srm"), _getContractAddr(core, "stableFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(core, "stableFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(core, "stableFeed"));

    LyraERC20(_getContractAddr(shared, "usdc")).configureMinter(deployer, true);

    // ETH

    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(ethMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(ethMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(ethMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(ethMarket, "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(ethMarket, "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(ethMarket, "iapFeed"));

    LyraRateFeedStatic(_getContractAddr(ethMarket, "rateFeed")).setRate(0, 1 ether);

    LyraERC20(_getContractAddr(shared, "eth")).configureMinter(deployer, true);

    // BTC

    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(btcMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(btcMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(btcMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(btcMarket, "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(btcMarket, "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(btcMarket, "iapFeed"));

    LyraRateFeedStatic(_getContractAddr(btcMarket, "rateFeed")).setRate(0, 1 ether);

    LyraERC20(_getContractAddr(shared, "btc")).configureMinter(deployer, true);

    // USDT

    _addWhitelistedCallee(_getContractAddr(core, "srm"), _getContractAddr(_readDeploymentFile("USDT"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("USDT"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("USDT"), "spotFeed"));

    LyraERC20(_getContractAddr(shared, "usdt")).configureMinter(deployer, true);

    // SNX

    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(snxMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(snxMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(snxMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(snxMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(snxMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(snxMarket, "forwardFeed"));

    LyraERC20(_getContractAddr(shared, "snx")).configureMinter(deployer, true);

    // WSTETH

    _addWhitelistedCallee(_getContractAddr(core, "srm"), _getContractAddr(_readDeploymentFile("WSTETH"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("WSTETH"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("WSTETH"), "spotFeed"));

    LyraERC20(_getContractAddr(shared, "wsteth")).configureMinter(deployer, true);


    // SOL

    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("SOL"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("SOL"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("SOL"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("SOL"), "iapFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("SOL"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("SOL"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("SOL"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("SOL"), "iapFeed"));

    // DOGE

    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("DOGE"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("DOGE"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("DOGE"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContractAddr(_readDeploymentFile("DOGE"), "iapFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("DOGE"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("DOGE"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("DOGE"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContractAddr(_readDeploymentFile("DOGE"), "iapFeed"));

    // Set custom caps for local testing

    WrappedERC20Asset(_getContractAddr(ethMarket, "base")).setTotalPositionCap(
      IManager(_getContractAddr(core, "srm")), 10_000 ether
    );
    WrappedERC20Asset(_getContractAddr(btcMarket, "base")).setTotalPositionCap(
      IManager(_getContractAddr(core, "srm")), 10_000 ether
    );
    WrappedERC20Asset(_getContractAddr(_readDeploymentFile("USDT"), "base")).setTotalPositionCap(
      IManager(_getContractAddr(core, "srm")), 100_000 ether
    );

    vm.stopBroadcast();
  }

  function _addWhitelistedCallee(address manager, address callee) internal {
    BaseManager(manager).setWhitelistedCallee(callee, true);
  }

  function _getPMRM(string memory marketData) internal returns (address) {
    return abi.decode(vm.parseJson(marketData, ".pmrm"), (address));
  }

  function _getContractAddr(string memory marketData, string memory key) internal returns (address) {
    return abi.decode(vm.parseJson(marketData, string.concat(".", key)), (address));
  }
}