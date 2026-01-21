pragma solidity ^0.8.20;

import "../src/Matching.sol";
import "../src/modules/RfqModule.sol";
import "../src/periphery/LyraSettlementUtils.sol";
import "../src/tokenizedSubaccounts/CCTSA.sol";
import "../src/tokenizedSubaccounts/PPTSA.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import "v2-core/src/SubAccounts.sol";
import "v2-core/src/assets/WLWrappedERC20Asset.sol";
import "v2-core/src/l2/LyraERC20.sol";
import "v2-core/src/risk-managers/PMRM_2_1.sol";
import {BaseTSA} from "../src/tokenizedSubaccounts/BaseTSA.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ForkBase} from "./ForkBase.t.sol";
import {IDepositModule} from "../src/interfaces/IDepositModule.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IMatching} from "../src/interfaces/IMatching.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {ITradeModule} from "../src/interfaces/ITradeModule.sol";
import {IWithdrawalModule} from "../src/interfaces/IWithdrawalModule.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import {LeveragedBasisTSA} from "../src/tokenizedSubaccounts/LevBasisTSA.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";
import {TokenizedSubAccount} from "../src/tokenizedSubaccounts/TSA.sol";
import {PMRMLib_2} from "v2-core/src/risk-managers/PMRMLib_2.sol";

contract DeriveForkUpgradePM2 is ForkBase {
  function setUp() external {}

  function testForkUpgrade() external checkFork {
    vm.assertEq(block.chainid, 957); // Owner is only prod

    address owner = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;

    PMRM_2_1 implementation = new PMRM_2_1();

    vm.deal(owner, 1 ether);
    vm.startPrank(owner);

    PMRM_2_1 pm2 = PMRM_2_1(_getV2CoreContract("ETH_2", "pmrm2"));

    (int mm, int mtm, uint worstScen) = pm2.getMarginAndMtM(53874, false);
    console.log("Margin before upgrade for", uint(53874));
    console.log("- MM:", mm);
    console.log("- MTM:", mtm);

    ProxyAdmin(_getV2CoreContract("ETH_2", "proxyAdmin")).upgradeAndCall(
      ITransparentUpgradeableProxy(address(pm2)),
      address(implementation),
      new bytes(0)
    );

    (mm, mtm, worstScen) = pm2.getMarginAndMtM(53874, false);
    console.log("Margin after upgrade for", uint(53874));
    console.log("- MM:", mm);
    console.log("- MTM:", mtm);

    PMRMLib_2 defaultLib = PMRMLib_2(address(pm2.lib()));
    PMRMLib_2 overrideLib = new PMRMLib_2();

    overrideLib.setBasisContingencyParams(defaultLib.getBasisContingencyParams());
    PMRMLib_2.MarginParameters memory marginParams = defaultLib.getMarginParams();
    marginParams.mmFactor = 0.35 ether;
    overrideLib.setMarginParams(marginParams);
    overrideLib.setVolShockParams(defaultLib.getVolShockParams());
    overrideLib.setSkewShockParameters(defaultLib.getSkewShockParams());
    overrideLib.setOtherContingencyParams(defaultLib.getOtherContingencyParams());

    address[] memory assets = SubAccounts(_getCoreContract("subAccounts")).getUniqueAssets(53874);

    for (uint i=0; i<assets.length; i++) {
      address asset = assets[i];
      ISpotFeed feed = pm2.collateralSpotFeeds(asset);
      if (feed != ISpotFeed(address(0))) {
        overrideLib.setCollateralParameters(asset, defaultLib.getCollateralParameters(asset));
      }
    }

    pm2.setLibOverride(53874, overrideLib);

    (mm, mtm, worstScen) = pm2.getMarginAndMtM(53874, false);
    console.log("Margin with override for", uint(53874));
    console.log("- MM:", mm);
    console.log("- MTM:", mtm);
  }
}
