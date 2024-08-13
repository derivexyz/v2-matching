pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
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



contract LyraForkUpgradeTest is Test {

  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
  .CollateralManagementParams({
    feeFactor: 10000000000000000,
    spotTransactionLeniency: 1050000000000000000,
    worstSpotSellPrice: 985000000000000000,
    worstSpotBuyPrice: 1015000000000000000
  });

  PrincipalProtectedTSA.PPTSAParams public defaultLrtppTSAParams = PrincipalProtectedTSA.PPTSAParams({
    maxMarkValueToStrikeDiffRatio  : 700000000000000000,
    minMarkValueToStrikeDiffRatio  : 100000000000000000,
    strikeDiff  : 200000000000000000000,
    maxTotalCostTolerance  : 2000000000000000000,
    maxLossOrGainPercentOfTVL  : 20000000000000000,
    negMaxCashTolerance  : 20000000000000000,
    minSignatureExpiry  : 300,
    maxSignatureExpiry  : 1800,
    optionMinTimeToExpiry  : 21000,
    optionMaxTimeToExpiry  : 691200,
    maxNegCash  : -100000000000000000000000,
    rfqFeeFactor  : 1000000000000000000
  });


  function setUp() external {}

  function testForkUpgrade() external {
    address deployer = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;
    
    vm.deal(deployer, 1 ether);
    vm.startPrank(deployer);
    string memory tsaName = "sUSDeBULL";

    StandardManager srm = StandardManager(_getContract("core", "srm"));
    ProxyAdmin proxyAdmin = ProxyAdmin(_getContract(tsaName, "proxyAdmin"));

    PrincipalProtectedTSA implementation = PrincipalProtectedTSA(_getContract(tsaName, "implementation"));

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(_getContract(tsaName, "proxy")),
      address(0xa2F1C5b4d8e0b3835025a9E5D45cFF6226261f58),
      abi.encodeWithSelector(
        implementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getContract("core", "subAccounts")),
          auction: DutchAuction(_getContract("core", "auction")),
          cash: CashAsset(_getContract("core", "cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getContract("sUSDe", "base")),
          manager: ILiquidatableManager(_getContract("core", "srm")),
          matching: IMatching(_getContract("matching", "matching")),
          symbol: tsaName,
          name: string.concat("sUSDe ", "Principal Protected Bull Call Spread")
        }),
        PrincipalProtectedTSA.PPTSAInitParams({
          baseFeed: ISpotFeed(_getContract("sUSDe", "spotFeed")),
          depositModule: IDepositModule(_getContract("matching", "deposit")),
          withdrawalModule: IWithdrawalModule(_getContract("matching", "withdrawal")),
          tradeModule: ITradeModule(_getContract("matching", "trade")),
          optionAsset: IOptionAsset(_getContract("ETH", "option")),
          rfqModule: IRfqModule(_getContract("matching", "rfq")),
          isCallSpread: true,
          isLongSpread: true
        })
      )
    );

    PrincipalProtectedTSA pptsa = PrincipalProtectedTSA(address(_getContract(tsaName, "proxy")));

    pptsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 100000000e18,
        minDepositValue: 0.01e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );
    pptsa.setPPTSAParams(defaultLrtppTSAParams);
    pptsa.setCollateralManagementParams(defaultCollateralManagementParams);

  }

  function _getContract(string memory file, string memory name) internal view returns (address) {
    string memory file = _readDeploymentFile(file);
    return abi.decode(vm.parseJson(file, string.concat(".", name)), (address));
  }

  ///@dev read deployment file from deployments/
  function _readDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }
}
