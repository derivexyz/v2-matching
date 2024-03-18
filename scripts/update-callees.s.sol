// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;


import {Matching} from "../src/Matching.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {RfqModule} from "../src/modules/RfqModule.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {PerpAsset} from "v2-core/src/assets/PerpAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {LyraRateFeedStatic} from "v2-core/src/feeds/LyraRateFeedStatic.sol";

import {WrappedERC20Asset} from "v2-core/src/assets/WrappedERC20Asset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {BaseManager} from "v2-core/src/risk-managers/BaseManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";

import {LyraERC20} from "v2-core/src/l2/LyraERC20.sol";

import "forge-std/console2.sol";
import {Deployment, NetworkConfig} from "./types.sol";
import {Utils} from "./utils.sol";


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

    _addWhitelistedCallee(_getContract(core, "srm"), _getContract(core, "stableFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(core, "stableFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(core, "stableFeed"));

    LyraERC20(_getContract(shared, "usdc")).configureMinter(deployer, true);

    // ETH

    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(ethMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(ethMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(ethMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(ethMarket, "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(ethMarket, "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(ethMarket, "iapFeed"));

    LyraRateFeedStatic(_getContract(ethMarket, "rateFeed")).setRate(0, 1 ether);

    LyraERC20(_getContract(shared, "eth")).configureMinter(deployer, true);

    // BTC

    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(btcMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(btcMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(btcMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(btcMarket, "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(btcMarket, "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(btcMarket, "iapFeed"));

    LyraRateFeedStatic(_getContract(btcMarket, "rateFeed")).setRate(0, 1 ether);

    LyraERC20(_getContract(shared, "btc")).configureMinter(deployer, true);

    // USDT

    _addWhitelistedCallee(_getContract(core, "srm"), _getContract(_readDeploymentFile("USDT"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(_readDeploymentFile("USDT"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(_readDeploymentFile("USDT"), "spotFeed"));

    LyraERC20(_getContract(shared, "usdt")).configureMinter(deployer, true);

    // SNX

    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(snxMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(snxMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(snxMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(snxMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(snxMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(snxMarket, "forwardFeed"));

    LyraERC20(_getContract(shared, "snx")).configureMinter(deployer, true);

    // WSTETH

    _addWhitelistedCallee(_getContract(core, "srm"), _getContract(_readDeploymentFile("WSTETH"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getContract(_readDeploymentFile("WSTETH"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getContract(_readDeploymentFile("WSTETH"), "spotFeed"));

    LyraERC20(_getContract(shared, "wsteth")).configureMinter(deployer, true);

    // Set custom caps for local testing

    WrappedERC20Asset(_getContract(ethMarket, "base")).setTotalPositionCap(
      IManager(_getContract(core, "srm")), 10_000 ether
    );
    WrappedERC20Asset(_getContract(btcMarket, "base")).setTotalPositionCap(
      IManager(_getContract(core, "srm")), 10_000 ether
    );
    WrappedERC20Asset(_getContract(_readDeploymentFile("USDT"), "base")).setTotalPositionCap(
      IManager(_getContract(core, "srm")), 100_000 ether
    );

    vm.stopBroadcast();
  }

  function _addWhitelistedCallee(address manager, address callee) internal {
    BaseManager(manager).setWhitelistedCallee(callee, true);
  }

  function _getPMRM(string memory marketData) internal returns (address) {
    return abi.decode(vm.parseJson(marketData, ".pmrm"), (address));
  }

  function _getContract(string memory marketData, string memory key) internal returns (address) {
    return abi.decode(vm.parseJson(marketData, string.concat(".", key)), (address));
  }
}