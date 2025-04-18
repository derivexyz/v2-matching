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
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenizedSubAccount} from "../src/tokenizedSubaccounts/TSA.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";
import {LeveragedBasisTSA, CollateralManagementTSA} from "../src/tokenizedSubaccounts/LevBasisTSA.sol";


contract DeployLBTSA is Utils {

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
    string memory marketName = vm.envString("DEPOSIT_ASSET");
    string memory vaultTokenName = string.concat(marketName, "B");
    string memory perpMarketName = vm.envString("PERP_ASSET");

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console.log("deployer: ", deployer);

    LeveragedBasisTSA lbtsaImplementation = new LeveragedBasisTSA();

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(lbtsaImplementation),
      address(deployer),
      abi.encodeWithSelector(
        lbtsaImplementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
          auction: DutchAuction(_getCoreContract("auction")),
          cash: CashAsset(_getCoreContract("cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getMarketAddress(marketName, "base")),
          manager: ILiquidatableManager(_getCoreContract("srm")),
          matching: IMatching(_getMatchingModule("matching")),
          symbol: vaultTokenName,
          name: string.concat(marketName, " Basis Trade")
        }),
        LeveragedBasisTSA.LBTSAInitParams({
          baseFeed: ISpotFeed(_getMarketAddress(marketName, "spotFeed")),
          depositModule: IDepositModule(_getMatchingModule("deposit")),
          withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
          tradeModule: ITradeModule(_getMatchingModule("trade")),
          perpAsset: IPerpAsset(_getMarketAddress(perpMarketName, "perp"))
        })
      )
    );

    LeveragedBasisTSA lbtsa = LeveragedBasisTSA(address(proxy));

    lbtsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000000e18,
        minDepositValue: 0,
        depositScale: 1e18,
        // slight withdrawal fee
        withdrawScale: 0.998e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );
    lbtsa.setLBTSAParams(defaultLbtsaTSAParams);
    lbtsa.setCollateralManagementParams(defaultCollateralManagementParams);

    string memory objKey = "tsa-deployment";
    vm.serializeAddress(objKey, "token", address(proxy));
    string memory finalObj = vm.serializeAddress(objKey, "implementation", address(lbtsaImplementation));

    // build path
    _writeToDeployments(vaultTokenName, finalObj);
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