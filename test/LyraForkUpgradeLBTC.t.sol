pragma solidity ^0.8.20;

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
import "v2-core/src/l2/LyraERC20.sol";
import "../src/Matching.sol";
import "v2-core/src/assets/WLWrappedERC20Asset.sol";
import "../src/modules/RfqModule.sol";
import "v2-core/src/SubAccounts.sol";
import {ForkBase} from "./ForkBase.t.sol";
import {LeveragedBasisTSA} from "../src/tokenizedSubaccounts/LevBasisTSA.sol";

contract LyraForkUpgradeTestLBTC is ForkBase {
  function setUp() external {}

  function testForkUpgrade() external checkFork {
    vm.assertEq(block.chainid, 957); // Owner is only prod

    address owner = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;

    LeveragedBasisTSA implementation = LeveragedBasisTSA(0x61B7A841965aC574E0f82644aD15327d50E7431C);

    vm.deal(owner, 1 ether);
    vm.startPrank(owner);

    {
      string memory marketName = "LBTC";
      string memory perpMarketName = "BTC";
      string memory vaultTokenName = string.concat("b", marketName);
      string memory vaultFileName = string.concat(marketName, "B");

      LeveragedBasisTSA tsa = LeveragedBasisTSA(_getMatchingContract(vaultFileName, "token"));

      BaseTSA.BaseTSAInitParams memory baseTsaInitParams = BaseTSA.BaseTSAInitParams({
        subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
        auction: DutchAuction(_getCoreContract("auction")),
        cash: CashAsset(_getCoreContract("cash")),
        wrappedDepositAsset: IWrappedERC20Asset(_getV2CoreContract(marketName, "base")),
        manager: ILiquidatableManager(_getCoreContract("srm")),
        matching: IMatching(_getMatchingModule("matching")),
        symbol: vaultTokenName,
        name: string.concat("Basis traded ", marketName)
      });

      LeveragedBasisTSA.LBTSAInitParams memory levBasisInitParams = LeveragedBasisTSA.LBTSAInitParams({
        baseFeed: ISpotFeed(_getV2CoreContract(marketName, "spotFeed")),
        depositModule: IDepositModule(_getMatchingModule("deposit")),
        withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
        tradeModule: ITradeModule(_getMatchingModule("trade")),
        perpAsset: IPerpAsset(_getV2CoreContract(perpMarketName, "perp"))
      });

      ProxyAdmin(_getMatchingContract(vaultFileName, "proxyAdmin")).upgradeAndCall(
        ITransparentUpgradeableProxy(_getMatchingContract(vaultFileName, "token")),
        address(implementation),
        abi.encodeWithSelector(implementation.initialize.selector, owner, baseTsaInitParams, levBasisInitParams)
      );

      tsa.isSigner(0x76a4A01f5159674e21196E9e68847694F5f2e988);
      tsa.setSubmitter(_getMatchingModule("atomicExecutor"), true);
    }

    {
      string memory marketName = "WEETH";
      string memory perpMarketName = "ETH";
      string memory vaultTokenName = string.concat("b", marketName);
      string memory vaultFileName = string.concat(marketName, "B");

      LeveragedBasisTSA tsa = LeveragedBasisTSA(_getMatchingContract(vaultFileName, "token"));

      BaseTSA.BaseTSAInitParams memory baseTsaInitParams = BaseTSA.BaseTSAInitParams({
        subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
        auction: DutchAuction(_getCoreContract("auction")),
        cash: CashAsset(_getCoreContract("cash")),
        wrappedDepositAsset: IWrappedERC20Asset(_getV2CoreContract(marketName, "base")),
        manager: ILiquidatableManager(_getCoreContract("srm")),
        matching: IMatching(_getMatchingModule("matching")),
        symbol: vaultTokenName,
        name: string.concat("Basis traded ", marketName)
      });

      LeveragedBasisTSA.LBTSAInitParams memory levBasisInitParams = LeveragedBasisTSA.LBTSAInitParams({
        baseFeed: ISpotFeed(_getV2CoreContract(marketName, "spotFeed")),
        depositModule: IDepositModule(_getMatchingModule("deposit")),
        withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
        tradeModule: ITradeModule(_getMatchingModule("trade")),
        perpAsset: IPerpAsset(_getV2CoreContract(perpMarketName, "perp"))
      });

      ProxyAdmin(_getMatchingContract(vaultFileName, "proxyAdmin")).upgradeAndCall(
        ITransparentUpgradeableProxy(_getMatchingContract(vaultFileName, "token")),
        address(implementation),
        abi.encodeWithSelector(implementation.initialize.selector, owner, baseTsaInitParams, levBasisInitParams)
      );

      tsa.isSigner(0x76a4A01f5159674e21196E9e68847694F5f2e988);
      tsa.setSubmitter(_getMatchingModule("atomicExecutor"), true);
    }
  }
}
