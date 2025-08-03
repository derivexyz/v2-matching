// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";
import "../src/periphery/LyraSettlementUtils.sol";
import {BaseTSA} from "../src/tokenizedSubaccounts/BaseTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IMatching} from "../src/interfaces/IMatching.sol";
import {IDepositModule} from "../src/interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../src/interfaces/IWithdrawalModule.sol";
import {ITradeModule} from "../src/interfaces/ITradeModule.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import "../src/tokenizedSubaccounts/CCTSA.sol";
import "../src/tokenizedSubaccounts/PPTSA.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenizedSubAccount} from "../src/tokenizedSubaccounts/TSA.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";
import {Vm} from "forge-std/Vm.sol";
import {FxToken} from "../src/FX/FXToken.sol";
import {WrappedERC20Asset} from "v2-core/src/assets/WrappedERC20Asset.sol";


contract DeployFXUSDC is Utils {
  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    string name = vm.envString("TOKEN_NAME");

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    FxToken fxTokenImplementation = new FxToken();

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(fxTokenImplementation),
      address(deployer),
      abi.encodeWithSelector(fxTokenImplementation.initialize.selector, name, "fxUSDC", 6)
    );


    FxToken fxUSDC = FxToken(address(proxy));

    console2.log("fxUSDC: ", address(fxUSDC));
    console2.log("fxUSDCImp: ", address(fxTokenImplementation));

    WrappedERC20Asset fxUSDCAsset = new WrappedERC20Asset(ISubAccounts(_loadConfig().subAccounts), fxUSDC);

    console2.log("fxUSDCAsset: ", address(fxUSDCAsset));
  }
}