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
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";

import {LyraERC20} from "v2-core/src/l2/LyraERC20.sol";

import "forge-std/console2.sol";
import {Deployment, NetworkConfig} from "./types.sol";
import {Utils} from "./utils.sol";
import {PMRM_2} from "v2-core/src/risk-managers/PMRM_2.sol";
import {PMRMLib_2, IPMRMLib_2} from "v2-core/src/risk-managers/PMRMLib_2.sol";

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

    address[] memory managers = new address[](3);
    managers[0] = _getV2CoreContract(core, "srm");
    managers[1] = _getPMRM(ethMarket);
    managers[2] = _getPMRM(btcMarket);

    for (uint i = 0; i < managers.length; ++i) {
      address manager = managers[i];
      // USDC
      _addWhitelistedCallee(manager, _getV2CoreContract(core, "stableFeed"));

      // ETH
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "spotFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "volFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "forwardFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "perpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "ibpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "iapFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(ethMarket, "rateFeed"));

      // BTC
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "spotFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "volFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "forwardFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "perpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "ibpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "iapFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(btcMarket, "rateFeed"));

      // USDT

      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("USDT"), "spotFeed"));

      // SNX
      _addWhitelistedCallee(manager, _getV2CoreContract(snxMarket, "spotFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(snxMarket, "volFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(snxMarket, "forwardFeed"));

      // WSTETH
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "spotFeed"));

      // SOL
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "spotFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "perpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "ibpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("SOL"), "iapFeed"));

      // DOGE
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "spotFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "perpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "ibpFeed"));
      _addWhitelistedCallee(manager, _getV2CoreContract(_readV2CoreDeploymentFile("DOGE"), "iapFeed"));

    }

    // Set custom caps for local testing
    LyraERC20(_getV2CoreContract(shared, "usdc")).configureMinter(deployer, true);
    LyraERC20(_getV2CoreContract(shared, "eth")).configureMinter(deployer, true);
    LyraERC20(_getV2CoreContract(shared, "btc")).configureMinter(deployer, true);
    LyraERC20(_getV2CoreContract(shared, "usdt")).configureMinter(deployer, true);
    LyraERC20(_getV2CoreContract(shared, "wsteth")).configureMinter(deployer, true);
    LyraERC20(_getV2CoreContract(shared, "snx")).configureMinter(deployer, true);

    WrappedERC20Asset(_getV2CoreContract(ethMarket, "base")).setTotalPositionCap(
      IManager(managers[0]), 10_000 ether
    );
    WrappedERC20Asset(_getV2CoreContract(btcMarket, "base")).setTotalPositionCap(
      IManager(managers[0]), 10_000 ether
    );
    WrappedERC20Asset(_getV2CoreContract(_readV2CoreDeploymentFile("USDT"), "base")).setTotalPositionCap(
      IManager(managers[0]), 100_000 ether
    );

    // setup collaterals and params for PMRM_2

    PMRM_2(_getV2MarketContract("ETH_2", "pmrm2")).setCollateralSpotFeed(
      _getV2CoreContract(btcMarket, "base"),
      ISpotFeed(_getV2CoreContract(btcMarket, "spotFeed"))
    );

    // Additional collateral spot feed mappings from the original script
    PMRM_2(_getV2MarketContract("ETH_2", "pmrm2")).setCollateralSpotFeed(
      _getV2CoreContract(btcMarket, "base"),
      ISpotFeed(_getV2CoreContract(btcMarket, "spotFeed"))
    );

    PMRM_2(_getV2MarketContract("ETH_2", "pmrm2")).setCollateralSpotFeed(
      _getV2CoreContract(ethMarket, "base"),
      ISpotFeed(_getV2CoreContract(ethMarket, "spotFeed"))
    );

    PMRM_2(_getV2MarketContract("BTC_2", "pmrm2")).setCollateralSpotFeed(
      _getV2CoreContract(ethMarket, "base"),
      ISpotFeed(_getV2CoreContract(ethMarket, "spotFeed"))
    );

    PMRM_2(_getV2MarketContract("BTC_2", "pmrm2")).setCollateralSpotFeed(
      _getV2CoreContract(btcMarket, "base"),
      ISpotFeed(_getV2CoreContract(btcMarket, "spotFeed"))
    );

    PMRM_2(_getV2MarketContract("BTC_2", "pmrm2")).setCollateralSpotFeed(
      _getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "base"),
      ISpotFeed(_getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "spotFeed"))
    );

    // Set collateral parameters on the PMRM lib contracts (pmrmLib2)
    // ETH market lib
    PMRMLib_2(_getV2MarketContract("ETH_2", "pmrmLib2")).setCollateralParameters(
      _getV2CoreContract(btcMarket, "base"),
      IPMRMLib_2.CollateralParameters({
        isEnabled: true,
        isRiskCancelling: false,
        MMHaircut: 0.07 ether,
        IMHaircut: 0.035 ether
      })
    );

    PMRMLib_2(_getV2MarketContract("ETH_2", "pmrmLib2")).setCollateralParameters(
      _getV2CoreContract(ethMarket, "base"),
      IPMRMLib_2.CollateralParameters({
        isEnabled: true,
        isRiskCancelling: true,
        MMHaircut: 0.01 ether,
        IMHaircut: 0.015 ether
      })
    );

    // BTC market lib
    PMRMLib_2(_getV2MarketContract("BTC_2", "pmrmLib2")).setCollateralParameters(
      _getV2CoreContract(ethMarket, "base"),
      IPMRMLib_2.CollateralParameters({
        isEnabled: true,
        isRiskCancelling: false,
        MMHaircut: 0.08 ether,
        IMHaircut: 0.025 ether
      })
    );

    PMRMLib_2(_getV2MarketContract("BTC_2", "pmrmLib2")).setCollateralParameters(
      _getV2CoreContract(btcMarket, "base"),
      IPMRMLib_2.CollateralParameters({
        isEnabled: true,
        isRiskCancelling: true,
        MMHaircut: 0.02 ether,
        IMHaircut: 0.025 ether
      })
    );

    PMRMLib_2(_getV2MarketContract("BTC_2", "pmrmLib2")).setCollateralParameters(
      _getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "base"),
      IPMRMLib_2.CollateralParameters({
        isEnabled: true,
        isRiskCancelling: false,
        MMHaircut: 0.03 ether,
        IMHaircut: 0.045 ether
      })
    );

    // Set total position caps (per original script values)
    WrappedERC20Asset(_getV2CoreContract(ethMarket, "base")).setTotalPositionCap(
      IManager(_getV2MarketContract("ETH_2", "pmrm2")), 750 ether
    );

    WrappedERC20Asset(_getV2CoreContract(ethMarket, "base")).setTotalPositionCap(
      IManager(_getV2MarketContract("BTC_2", "pmrm2")), 1500 ether
    );

    WrappedERC20Asset(_getV2CoreContract(btcMarket, "base")).setTotalPositionCap(
      IManager(_getV2MarketContract("ETH_2", "pmrm2")), 1750 ether
    );

    WrappedERC20Asset(_getV2CoreContract(btcMarket, "base")).setTotalPositionCap(
      IManager(_getV2MarketContract("BTC_2", "pmrm2")), 3500 ether
    );

    WrappedERC20Asset(_getV2CoreContract(_readV2CoreDeploymentFile("WSTETH"), "base")).setTotalPositionCap(
      IManager(_getV2MarketContract("BTC_2", "pmrm2")), 125 ether
    );

    // Whitelist the pmrm managers on base assets
    WrappedERC20Asset(_getV2CoreContract(ethMarket, "base")).setWhitelistManager(
      _getV2MarketContract("ETH_2", "pmrm2"), true
    );

    WrappedERC20Asset(_getV2CoreContract(btcMarket, "base")).setWhitelistManager(
      _getV2MarketContract("BTC_2", "pmrm2"), true
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

  function _getV2MarketContract(string memory marketName, string memory key) internal returns (address) {
    string memory marketData = _readV2CoreDeploymentFile(marketName);
    return _getV2CoreContract(marketData, key);
  }
}