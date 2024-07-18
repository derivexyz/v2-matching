// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

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


contract DeployTSA is Utils {

  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
  .CollateralManagementParams({
    feeFactor: 0.01e18,
    spotTransactionLeniency: 1.05e18,
    worstSpotSellPrice: 0.985e18,
    worstSpotBuyPrice: 1.015e18
  });

  CoveredCallTSA.CCTSAParams public defaultLrtccTSAParams = CoveredCallTSA.CCTSAParams({
    minSignatureExpiry: 1 minutes,
    maxSignatureExpiry: 15 minutes,
    optionVolSlippageFactor: 0.8e18,
    optionMaxDelta: 0.2e18,
    optionMaxNegCash: -100_000e18,
    optionMinTimeToExpiry: 6 days,
    optionMaxTimeToExpiry: 8 days
  });

  PrincipalProtectedTSA.PPTSAParams public defaultLrtppTSAParams = PrincipalProtectedTSA.PPTSAParams({
    maxMarkValueToStrikeDiffRatio: 1e17,
    minMarkValueToStrikeDiffRatio: 1e16,
    strikeDiff: 400e18,
    maxTotalCostTolerance: 2.5e18,
    maxLossPercentOfTVL: 1e17,
    negMaxCashTolerance: 1e17,
    minSignatureExpiry: 5 minutes,
    maxSignatureExpiry: 30 minutes,
    optionMinTimeToExpiry: 6 days,
    optionMaxTimeToExpiry: 8 days
  });

  function run() external {
    // upgradeCCTSA();
    upgradePPTSA();
  }

    /// @dev main function
  function upgradeCCTSA() private {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    string memory marketName = vm.envString("MARKET_NAME");
    string memory tsaName = string.concat(marketName, "C");

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    ProxyAdmin proxyAdmin = ProxyAdmin(_getMarketAddress(tsaName, "proxyAdmin"));
    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(_getMarketAddress(tsaName, "proxy")));

    CoveredCallTSA lrtcctsaImplementation = CoveredCallTSA(_getMarketAddress(tsaName, "implementation"));

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(lrtcctsaImplementation),
      abi.encodeWithSelector(
        lrtcctsaImplementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
          auction: DutchAuction(_getCoreContract("auction")),
          cash: CashAsset(_getCoreContract("cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getMarketAddress(marketName, "base")),
          manager: ILiquidatableManager(_getCoreContract("srm")),
          matching: IMatching(_getMatchingModule("matching")),
          symbol: tsaName,
          name: string.concat(marketName, " Covered Call")
        }),
        CoveredCallTSA.CCTSAInitParams({
          baseFeed: ISpotFeed(_getMarketAddress(marketName, "spotFeed")),
          depositModule: IDepositModule(_getMatchingModule("deposit")),
          withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
          tradeModule: ITradeModule(_getMatchingModule("trade")),
          optionAsset: IOptionAsset(_getMarketAddress("ETH", "option"))
        })
      )
    );

    CoveredCallTSA(address(proxy)).setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000000e18,
        minDepositValue: 0.01e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0.015e18,
        // TODO: Mainnet fee recipient should be different
        feeRecipient: address(deployer)
      })
    );
    CoveredCallTSA(address(proxy)).setCCTSAParams(defaultCollateralManagementParams, defaultLrtccTSAParams);
  }

  function upgradePPTSA() private {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    string memory marketName = vm.envString("MARKET_NAME");
    string memory tsaName = string.concat(marketName, "Bull");

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    ProxyAdmin proxyAdmin = ProxyAdmin(_getMarketAddress(tsaName, "proxyAdmin"));
    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(_getMarketAddress(tsaName, "proxy")));

    PrincipalProtectedTSA lrtpptsaImplementation = new PrincipalProtectedTSA();

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(lrtpptsaImplementation),
      abi.encodeWithSelector(
        lrtpptsaImplementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
          auction: DutchAuction(_getCoreContract("auction")),
          cash: CashAsset(_getCoreContract("cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getMarketAddress(marketName, "base")),
          manager: ILiquidatableManager(_getCoreContract("srm")),
          matching: IMatching(_getMatchingModule("matching")),
          symbol: tsaName,
          name: string.concat(marketName, "Principal Protected Bull Call Spread")
        }),
        PrincipalProtectedTSA.PPTSAInitParams({
          baseFeed: ISpotFeed(_getMarketAddress(marketName, "spotFeed")),
          depositModule: IDepositModule(_getMatchingModule("deposit")),
          withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
          tradeModule: ITradeModule(_getMatchingModule("trade")),
          optionAsset: IOptionAsset(_getMarketAddress("ETH", "option")),
          rfqModule: IRfqModule(_getMatchingModule("rfq")),
          isCallSpread: true,
          isLongSpread: true
        })
      )
    );

    PrincipalProtectedTSA(address(proxy)).setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 100000000e18,
        minDepositValue: 0.01e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );
    PrincipalProtectedTSA(address(proxy)).setPPTSAParams(defaultCollateralManagementParams, defaultLrtppTSAParams);
  }

  function _getMatchingModule(string memory module) internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile("matching"), string.concat(".", module)), (address));
  }

  function _getMarketAddress(string memory marketName, string memory contractName) internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile(marketName), string.concat(".", contractName)), (address));
  }

  function _getCoreContract(string memory contractName) internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile("core"), string.concat(".", contractName)), (address));
  }
}