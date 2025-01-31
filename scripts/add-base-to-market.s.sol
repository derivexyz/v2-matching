// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./shared/Utils.sol";
import "forge-std/console.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "./config/config.sol";
import "v2-core/src/feeds/SFPSpotFeed.sol";
import {BasePortfolioViewer} from "v2-core/src/risk-managers/BasePortfolioViewer.sol";
import {Deployment, ConfigJson, Market} from "v2-core/scripts/types.sol";
import {IForwardFeed} from "v2-core/src/interfaces/IForwardFeed.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IPMRM} from "v2-core/src/interfaces/IPMRM.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IStandardManager} from "v2-core/src/interfaces/IStandardManager.sol";
import {StandardManager} from "v2-core/src/risk-managers/StandardManager.sol";
import {SRMPortfolioViewer} from "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import {IVolFeed} from "v2-core/src/interfaces/IVolFeed.sol";
import {LyraForwardFeed} from "v2-core/src/feeds/LyraForwardFeed.sol";
import {LyraRateFeedStatic} from "v2-core/src/feeds/static/LyraRateFeedStatic.sol";
import {LyraSpotDiffFeed} from "v2-core/src/feeds/LyraSpotDiffFeed.sol";

import {LyraSpotFeed} from "v2-core/src/feeds/LyraSpotFeed.sol";

import {LyraVolFeed} from "v2-core/src/feeds/LyraVolFeed.sol";
import {OptionAsset} from "v2-core/src/assets/OptionAsset.sol";

// get all default params
import {PMRMLib} from "v2-core/src/risk-managers/PMRMLib.sol";
import {PMRM} from "v2-core/src/risk-managers/PMRM.sol";
import {PerpAsset} from "v2-core/src/assets/PerpAsset.sol";
import {Utils} from "./utils.sol";
import {WrappedERC20Asset} from "v2-core/src/assets/WrappedERC20Asset.sol";

import "v2-core/scripts/utils.sol" as V2CoreUtils;

/**
 * MARKET_NAME=usdt forge script scripts/deploy-base-only-market.s.sol --private-key {} --rpc {} --broadcast
 **/
contract DeployMarket is UtilBase {

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    // revert if not found
    string memory marketName = vm.envString("MARKET_NAME");
    uint256 marketId = vm.envUint("MARKET_ID");

    console.log("Start deploying new market: ", marketName);
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: ", deployer);

    address marketERC20 = _getV2CoreContract("shared", vm.toLowercase(marketName));
    WrappedERC20Asset base = new WrappedERC20Asset(
      ISubAccounts(_getV2CoreContract("core", "subAccounts")),
      IERC20Metadata(marketERC20)
    );

    _whitelistAndSetCapForManager(_getV2CoreContract("core", "srm"), marketName, base);

    if (block.chainid != 957) {
      _addToMarketInSRM(marketName, marketId, base);
    }

    console.log("New asset deployed:", address(base));

    vm.stopBroadcast();
  }

  /// @dev deploy all contract needed for a single market
  function _deployMarketContracts(string memory marketName) internal returns (Market memory market)  {
    // get the market ERC20 from config (it should be added to the config)
    address marketERC20;
    if ((keccak256(abi.encodePacked(marketName)) == keccak256(abi.encodePacked("SFP")))) {
      marketERC20 = _getV2CoreContract("strands", "sfp");
      // cast as LyraSpotFeed for simplicity
      market.spotFeed = LyraSpotFeed(address(new SFPSpotFeed(IStrandsSFP(marketERC20))));
    } else {
      marketERC20 = _getV2CoreContract("shared", vm.toLowercase(marketName));

      console.log("target erc20:", marketERC20);

      market.spotFeed = new LyraSpotFeed();

      // init feeds
      market.spotFeed.setHeartbeat(Config.SPOT_HEARTBEAT);

      address[] memory feedSigners = _getV2CoreAddressArray("shared", "feedSigners");

      for (uint i = 0; i < feedSigners.length; ++i) {
        market.spotFeed.addSigner(feedSigners[i], true);
      }
      market.spotFeed.setRequiredSigners(uint8(_getV2CoreUint("shared", "requiredSigners")));
    }

    market.base = new WrappedERC20Asset(ISubAccounts(_getV2CoreContract("core", "subAccounts")), IERC20Metadata(marketERC20));
  }


  function _addToMarketInSRM(string memory marketName, uint marketId, WrappedERC20Asset base) internal {
    StandardManager srm = StandardManager(_getV2CoreContract("core", "srm"));
    SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getV2CoreContract("core", "srmViewer"));

    console.log("market ID for newly created market:", marketId);

    (,,IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      IStandardManager.BaseMarginParams memory baseMarginParams) = Config.getSRMParams(marketName);

    // set assets per market
    srm.whitelistAsset(base, marketId, IStandardManager.AssetType.Base);

//    srm.setOraclesForMarket(marketId, market.spotFeed, IForwardFeed(address(0)), IVolFeed(address(0)));
    srm.setOracleContingencyParams(marketId, oracleContingencyParams);
    srm.setBaseAssetMarginFactor(marketId, baseMarginParams.marginFactor, baseMarginParams.IMScale);

    srmViewer.setOIFeeRateBPS(address(base), Config.OI_FEE_BPS);

//    srm.setWhitelistedCallee(address(market.spotFeed), true);
  }

  function _whitelistAndSetCapForManager(address manager, string memory marketName, WrappedERC20Asset base) internal {
    base.setWhitelistManager(manager, true);

    (, , uint baseCap) = Config.getSRMCaps(marketName);

    base.setTotalPositionCap(IManager(manager), baseCap);
  }

}