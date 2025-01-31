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
import {LyraRateFeedStatic} from "v2-core/src/feeds/static/LyraRateFeedStatic.sol";

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

    string memory shared = _readV2CoreDeploymentFile("shared");
    string memory core = _readV2CoreDeploymentFile("core");
    string memory ethMarket = _readV2CoreDeploymentFile("ETH");
    string memory btcMarket = _readV2CoreDeploymentFile("BTC");
    string memory snxMarket = _readV2CoreDeploymentFile("SNX");

    // USDC

    _addWhitelistedCallee(_getV2CoreContract(core, "srm"), _getV2CoreContract(core, "stableFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(core, "stableFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(core, "stableFeed"));

    LyraERC20(_getV2CoreContract(shared, "usdc")).configureMinter(deployer, true);

    // ETH

    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(ethMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(ethMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(ethMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(ethMarket, "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(ethMarket, "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(ethMarket, "iapFeed"));

    LyraRateFeedStatic(_getV2CoreContract(ethMarket, "rateFeed")).setRate(0, 1 ether);

    LyraERC20(_getV2CoreContract(shared, "eth")).configureMinter(deployer, true);

    // BTC

    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(btcMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(btcMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(btcMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(btcMarket, "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(btcMarket, "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(btcMarket, "iapFeed"));

    LyraRateFeedStatic(_getV2CoreContract(btcMarket, "rateFeed")).setRate(0, 1 ether);

    LyraERC20(_getV2CoreContract(shared, "btc")).configureMinter(deployer, true);

    // USDT

    _addWhitelistedCallee(_getV2CoreContract(core, "srm"), _getV2CoreContract(_readV2CoreDeploymentFile("USDT"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("USDT"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("USDT"), "spotFeed"));

    LyraERC20(_getV2CoreContract(shared, "usdt")).configureMinter(deployer, true);

    // SNX

    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(snxMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(snxMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(snxMarket, "forwardFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(snxMarket, "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(snxMarket, "volFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(snxMarket, "forwardFeed"));

    LyraERC20(_getV2CoreContract(shared, "snx")).configureMinter(deployer, true);

    // WSTETH

    _addWhitelistedCallee(_getV2CoreContract(core, "srm"), _getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "spotFeed"));

    LyraERC20(_getV2CoreContract(shared, "wsteth")).configureMinter(deployer, true);


    // SOL

    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "iapFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "iapFeed"));

    // DOGE

    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(ethMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "iapFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "spotFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "perpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "ibpFeed"));
    _addWhitelistedCallee(_getPMRM(btcMarket), _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "iapFeed"));

    // Set custom caps for local testing

    WrappedERC20Asset(_getV2CoreContract(ethMarket, "base")).setTotalPositionCap(
      IManager(_getV2CoreContract(core, "srm")), 10_000 ether
    );
    WrappedERC20Asset(_getV2CoreContract(btcMarket, "base")).setTotalPositionCap(
      IManager(_getV2CoreContract(core, "srm")), 10_000 ether
    );
    WrappedERC20Asset(_getV2CoreContract(_readV2CoreDeploymentFile("USDT"), "base")).setTotalPositionCap(
      IManager(_getV2CoreContract(core, "srm")), 100_000 ether
    );

    vm.stopBroadcast();
  }

  function _addWhitelistedCallee(address manager, address callee) internal {
    BaseManager(manager).setWhitelistedCallee(callee, true);
  }

  function _getPMRM(string memory marketData) internal returns (address) {
    return abi.decode(vm.parseJson(marketData, ".pmrm"), (address));
  }

  function _getV2CoreContract(string memory marketData, string memory key) internal returns (address) {
    return abi.decode(vm.parseJson(marketData, string.concat(".", key)), (address));
  }
}