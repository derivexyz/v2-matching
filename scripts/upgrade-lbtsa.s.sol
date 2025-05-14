// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import {Utils} from "./utils.sol";
import "../src/periphery/LyraSettlementUtils.sol";
import {BaseTSA} from "../src/tokenizedSubaccounts/shared/BaseTSA.sol";
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
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenizedSubAccount} from "../src/tokenizedSubaccounts/TSA.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";
import {LeveragedBasisTSA, CollateralManagementTSA} from "../src/tokenizedSubaccounts/LevBasisTSA.sol";
import {UtilBase} from "./shared/Utils.sol";


contract UpgradeLBTSA is UtilBase {

  LeveragedBasisTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
  .CollateralManagementParams({
    feeFactor: 0.01e18,
    spotTransactionLeniency: 0,
    worstSpotSellPrice: 0,
    worstSpotBuyPrice: 0
  });

  LeveragedBasisTSA.LBTSAParams public defaultLbtsaTSAParams = LeveragedBasisTSA.LBTSAParams({
    maxPerpFee: 0.01e18,
    maxBaseLossPerBase: 0.02e18,
    maxBaseLossPerPerp: 0.02e18,
    deltaFloor: 0.7e18,
    deltaCeil: 1.3e18,
    leverageFloor: 0.95e18,
    leverageCeil: 3.05e18,
    emaDecayFactor: 0.0002e18,
    markLossEmaTarget: 0.015e18,
    minSignatureExpiry: 0,
    maxSignatureExpiry: 30 minutes
  });

  /// @dev main function
  function run() external {
    deployLBTSA();
  }

  function deployLBTSA() private {
    if (block.chainid != 901) {
      revert("Only deploy on testnet");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console.log("deployer: ", deployer);
    address owner = deployer;

    LeveragedBasisTSA implementation = new LeveragedBasisTSA();


    // bLBTC

    string memory marketName = "LBTC";
    string memory vaultName = "LBTCB";
    string memory perpName = "BTC";

    ProxyAdmin proxyAdmin = ProxyAdmin(_getMatchingContract(vaultName, "proxyAdmin"));
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(_getMatchingContract(vaultName, "token"));
//    console.log("proxyAdmin: ", address(proxyAdmin));
//    console.log("proxy: ", address(proxy));
//    console.log("implementation: ", address(implementation));
//    proxyAdmin.upgrade(proxy, address(implementation));
////    proxyAdmin.transferOwnership(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);
//
//    console.log("proxyAdmin: ", address(proxyAdmin));
//    console.log("proxy: ", address(proxy));
//    console.log("implementation: ", address(implementation));

    proxyAdmin.upgradeAndCall(proxy, address(implementation), abi.encodeWithSelector(
      implementation.initialize.selector,
      deployer,
      BaseTSA.BaseTSAInitParams({
        subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
        auction: DutchAuction(_getCoreContract("auction")),
        cash: CashAsset(_getCoreContract("cash")),
        wrappedDepositAsset: IWrappedERC20Asset(_getV2CoreContract(marketName, "base")),
        manager: ILiquidatableManager(_getCoreContract("srm")),
        matching: IMatching(_getMatchingContract("matching", "matching")),
        symbol: string.concat("b", marketName),
        name: string.concat("Basis traded ", marketName),
        initialParams: defaultLbtsaTSAParams
      }),
      LeveragedBasisTSA.LBTSAInitParams({
        baseFeed: ISpotFeed(_getV2CoreContract(marketName, "spotFeed")),
        depositModule: IDepositModule(_getMatchingContract("matching","deposit")),
        withdrawalModule: IWithdrawalModule(_getMatchingContract("matching","withdrawal")),
        tradeModule: ITradeModule(_getMatchingContract("matching","trade")),
        perpAsset: IPerpAsset(_getV2CoreContract(perpName, "perp"))
      })
    ));

    LeveragedBasisTSA(address(proxy)).setSubmitter(0x47E946f9027B0e7E0117afa482AF4C4053C53b40, true);
//
//    LeveragedBasisTSA(address(proxy)).setLBTSAParams();
//    LeveragedBasisTSA(address(proxy)).setCollateralManagementParams(defaultCollateralManagementParams);
////    proxyAdmin.transferOwnership(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    // bweETH

    marketName = "weETH";
    vaultName = "weETHB";
    perpName = "ETH";

    proxyAdmin = ProxyAdmin(_getMatchingContract(vaultName, "proxyAdmin"));
    proxy = ITransparentUpgradeableProxy(_getMatchingContract(vaultName, "token"));

    console.log("proxyAdmin: ", address(proxyAdmin));
    console.log("proxy: ", address(proxy));

    proxyAdmin.upgradeAndCall(proxy, address(implementation), abi.encodeWithSelector(
      implementation.initialize.selector,
      deployer,
      BaseTSA.BaseTSAInitParams({
        subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
        auction: DutchAuction(_getCoreContract("auction")),
        cash: CashAsset(_getCoreContract("cash")),
        wrappedDepositAsset: IWrappedERC20Asset(_getV2CoreContract(marketName, "base")),
        manager: ILiquidatableManager(_getCoreContract("srm")),
        matching: IMatching(_getMatchingContract("matching", "matching")),
        symbol: string.concat("b", marketName),
        name: string.concat("Basis traded ", marketName),
        initialParams: defaultLbtsaTSAParams
      }),
      LeveragedBasisTSA.LBTSAInitParams({
        baseFeed: ISpotFeed(_getV2CoreContract(marketName, "spotFeed")),
        depositModule: IDepositModule(_getMatchingContract("matching","deposit")),
        withdrawalModule: IWithdrawalModule(_getMatchingContract("matching","withdrawal")),
        tradeModule: ITradeModule(_getMatchingContract("matching","trade")),
        perpAsset: IPerpAsset(_getV2CoreContract(perpName, "perp"))
      })
    ));

    LeveragedBasisTSA(address(proxy)).setSubmitter(0x47E946f9027B0e7E0117afa482AF4C4053C53b40, true);

//    console.log("implementation: ", address(implementation));

//    LeveragedBasisTSA(address(proxy)).setLBTSAParams();
//    LeveragedBasisTSA(address(proxy)).setCollateralManagementParams(defaultCollateralManagementParams);
//    proxyAdmin.transferOwnership(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);


  }
}