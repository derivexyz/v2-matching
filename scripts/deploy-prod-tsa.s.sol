// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";
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


contract DeployTSA is Utils {

  enum VaultType {
    CoveredCall,
    PrincipalProtected
  }

  struct DeploySettings {
    VaultType vaultType;
    string depositAssetName;
    string optionAssetName;
    string vaultSymbol;
    string vaultName;
    bool ppTSAisCallSpread;
    bool ppTSAisLongSpread;
  }

  //////////////////////////////////////////
  // Settings - MUST CHANGE BEFORE DEPLOY //
  //////////////////////////////////////////

  DeploySettings public settings = DeploySettings({
    vaultType: VaultType.CoveredCall,
    depositAssetName: "weETH",
    optionAssetName: "ETH",
    vaultSymbol: "weETHBULL",
    vaultName: "weETH Principal Protected Bull Call Spread",
    ppTSAisCallSpread: true,
    ppTSAisLongSpread: true
  });

  BaseTSA.TSAParams public defaultBaseTSAParams = BaseTSA.TSAParams({
    depositCap: 10000000e18,
    minDepositValue: 0,
    depositScale: 1e18,
    withdrawScale: 1e18,
    managementFee: 0,
    feeRecipient: address(0)
  });

  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
  .CollateralManagementParams({
    feeFactor: 10000000000000000,
    spotTransactionLeniency: 1050000000000000000,
    worstSpotSellPrice: 980000000000000000,
    worstSpotBuyPrice: 1020000000000000000
  });

  CoveredCallTSA.CCTSAParams public defaultLrtccTSAParams = CoveredCallTSA.CCTSAParams({
    minSignatureExpiry: 5 minutes,
    maxSignatureExpiry: 30 minutes,
    optionVolSlippageFactor: 0.5e18,
    optionMaxDelta: 0.4e18,
    optionMaxNegCash: - 100e18,
    optionMinTimeToExpiry: 1 days,
    optionMaxTimeToExpiry: 30 days
  });

  PrincipalProtectedTSA.PPTSAParams public defaultLrtppTSAParams = PrincipalProtectedTSA.PPTSAParams({
    maxMarkValueToStrikeDiffRatio: 700000000000000000,
    minMarkValueToStrikeDiffRatio: 100000000000000000,
    strikeDiff: 200000000000000000000,
    maxTotalCostTolerance: 2000000000000000000,
    maxLossOrGainPercentOfTVL: 20000000000000000,
    negMaxCashTolerance: 20000000000000000,
    minSignatureExpiry: 300,
    maxSignatureExpiry: 1800,
    optionMinTimeToExpiry: 21000,
    optionMaxTimeToExpiry: 691200,
    maxNegCash: -100000000000000000000000,
    rfqFeeFactor: 1000000000000000000
  });

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console.log("deployer: ", deployer);

    // hardcode weETHC for getting proxyAdmin
    ProxyAdmin proxyAdmin = ProxyAdmin(_getMarketAddress("weETHC", "proxyAdmin"));

    if (settings.vaultType == VaultType.CoveredCall) {
      deployCoveredCall(proxyAdmin, deployer);
    } else {
      deployPrincipalProtected(proxyAdmin, deployer);
    }
  }

  function deployCoveredCall(ProxyAdmin proxyAdmin, address deployer) private {
    // TODO: We don't fetch the existing implementation yet as it has changed - collateralManagement factored out
    CoveredCallTSA lrtcctsaImplementation = new CoveredCallTSA();

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(lrtcctsaImplementation),
      address(proxyAdmin),
      abi.encodeWithSelector(
        lrtcctsaImplementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
          auction: DutchAuction(_getCoreContract("auction")),
          cash: CashAsset(_getCoreContract("cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getMarketAddress(settings.depositAssetName, "base")),
          manager: ILiquidatableManager(_getCoreContract("srm")),
          matching: IMatching(_getMatchingModule("matching")),
          symbol: settings.vaultSymbol,
          name: settings.vaultName
        }),
        CoveredCallTSA.CCTSAInitParams({
          baseFeed: ISpotFeed(_getMarketAddress(settings.depositAssetName, "spotFeed")),
          depositModule: IDepositModule(_getMatchingModule("deposit")),
          withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
          tradeModule: ITradeModule(_getMatchingModule("trade")),
          optionAsset: IOptionAsset(_getMarketAddress(settings.optionAssetName, "option"))
        })
      )
    );

    console.log("proxy: ", address(proxy));

    CoveredCallTSA(address(proxy)).setTSAParams(defaultBaseTSAParams);
    CoveredCallTSA cctsa = CoveredCallTSA(address(proxy));
    cctsa.setCCTSAParams(defaultLrtccTSAParams);
    cctsa.setCollateralManagementParams(defaultCollateralManagementParams);


    string memory objKey = "tsa-deployment";

    vm.serializeAddress(objKey, "proxyAdmin", address(proxyAdmin));
    vm.serializeAddress(objKey, "implementation", address(lrtcctsaImplementation));
    string memory finalObj = vm.serializeAddress(objKey, "proxy", address(proxy));

    _writeToDeployments(settings.vaultSymbol, finalObj);
  }

  function deployPrincipalProtected(ProxyAdmin proxyAdmin, address deployer) private {
    // hardcoded to get existing implementation of pptsa
    PrincipalProtectedTSA lrtpptsaImplementation = PrincipalProtectedTSA(_getMarketAddress("sUSDeBULL", "implementation"));

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(lrtpptsaImplementation),
      address(proxyAdmin),
      abi.encodeWithSelector(
        lrtpptsaImplementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
          auction: DutchAuction(_getCoreContract("auction")),
          cash: CashAsset(_getCoreContract("cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getMarketAddress(settings.depositAssetName, "base")),
          manager: ILiquidatableManager(_getCoreContract("srm")),
          matching: IMatching(_getMatchingModule("matching")),
          symbol: settings.vaultSymbol,
          name: settings.vaultName
        }),
        PrincipalProtectedTSA.PPTSAInitParams({
          baseFeed: ISpotFeed(_getMarketAddress(settings.depositAssetName, "spotFeed")),
          depositModule: IDepositModule(_getMatchingModule("deposit")),
          withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
          tradeModule: ITradeModule(_getMatchingModule("trade")),
          optionAsset: IOptionAsset(_getMarketAddress(settings.optionAssetName, "option")),
          rfqModule: IRfqModule(_getMatchingModule("rfq")),
          isCallSpread: settings.ppTSAisCallSpread,
          isLongSpread: settings.ppTSAisLongSpread
        })
      )
    );

    console.log("proxy: ", address(proxy));

    PrincipalProtectedTSA pptsa = PrincipalProtectedTSA(address(proxy));

    pptsa.setTSAParams(defaultBaseTSAParams);
    pptsa.setPPTSAParams(defaultLrtppTSAParams);
    pptsa.setCollateralManagementParams(defaultCollateralManagementParams);

    string memory objKey = "tsa-deployment";

    vm.serializeAddress(objKey, "proxyAdmin", address(proxyAdmin));
    vm.serializeAddress(objKey, "implementation", address(lrtpptsaImplementation));
    string memory finalObj = vm.serializeAddress(objKey, "proxy", address(proxy));

    // build path
    _writeToDeployments(settings.vaultSymbol, finalObj);
  }


  function _getMatchingModule(string memory module) internal returns (address) {
    return abi.decode(vm.parseJson(_readMatchingDeploymentFile("matching"), string.concat(".", module)), (address));
  }

  function _getMarketAddress(string memory marketName, string memory contractName) internal returns (address) {
    return abi.decode(vm.parseJson(_readV2CoreDeploymentFile(marketName), string.concat(".", contractName)), (address));
  }

  function _getCoreContract(string memory contractName) internal returns (address) {
    return abi.decode(vm.parseJson(_readV2CoreDeploymentFile("core"), string.concat(".", contractName)), (address));
  }
}