pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "v2-core/scripts/types.sol";
import "forge-std/console2.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./ForkBase.t.sol";
import {ITradeModule} from "../src/interfaces/ITradeModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import "../scripts/config/config.sol";
import {PositionTracking} from "v2-core/src/assets/utils/PositionTracking.sol";
import {WLWrappedERC20Asset} from "v2-core/src/assets/WLWrappedERC20Asset.sol";

contract LyraForkAddPerpTest is ForkBase {
  string[1] private markets = ["TRUMP"];

  string[4] public feeds = ["spotFeed", "perpFeed", "iapFeed", "ibpFeed"];
  string[2] public modules = ["trade", "rfq"];

  function setUp() external {}

  function testFork() external checkFork {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getV2CoreContract("core", "srm"));
    SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getV2CoreContract("core", "srmViewer"));

    PMRM ethPMRM = PMRM(_getV2CoreContract("ETH", "pmrm"));
    PMRM btcPMRM = PMRM(_getV2CoreContract("BTC", "pmrm"));

    for (uint i = 0; i < markets.length; i++) {
      console.log("market:", markets[i]);

      uint marketId =
        abi.decode(_call(address(srm), abi.encodeWithSelector(srm.createMarket.selector, markets[i])), (uint));

      console.log("market ID for market:", marketId);

      (
        IStandardManager.PerpMarginRequirements memory perpMarginReqs,
        ,
        IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      ) = Config.getSRMParams("OP");

      _call(
        address(srm),
        abi.encodeWithSelector(
          srm.setOraclesForMarket.selector,
          marketId,
          _getV2CoreContract(markets[i], "spotFeed"),
          IForwardFeed(address(0)),
          IVolFeed(address(0))
        )
      );

      _call(
        address(srm),
        abi.encodeWithSelector(
          srm.whitelistAsset.selector,
          _getV2CoreContract(markets[i], "perp"),
          marketId,
          IStandardManager.AssetType.Perpetual
        )
      );

      _call(
        address(srm),
        abi.encodeWithSelector(
          srm.setPerpMarginRequirements.selector, marketId, perpMarginReqs.mmPerpReq, perpMarginReqs.imPerpReq
        )
      );

      _call(
        address(srm), abi.encodeWithSelector(srm.setOracleContingencyParams.selector, marketId, oracleContingencyParams)
      );

      _call(
        _getV2CoreContract("core", "srmViewer"),
        abi.encodeWithSelector(
          srmViewer.setOIFeeRateBPS.selector, address(_getV2CoreContract(markets[i], "perp")), Config.OI_FEE_BPS
        )
      );

      _call(
        address(_getV2CoreContract(markets[i], "perp")), abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)
      );

      ////////////////////
      // Whitelist callee for feeds/accept ownership
      ////////////////////

      for (uint j = 0; j < feeds.length; j++) {
        _call(
          address(_getV2CoreContract(markets[i], feeds[j])),
          abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)
        );

        _call(
          address(srm),
          abi.encodeWithSelector(
            srm.setWhitelistedCallee.selector, address(_getV2CoreContract(markets[i], feeds[j])), true
          )
        );

        _call(
          address(btcPMRM),
          abi.encodeWithSelector(
            srm.setWhitelistedCallee.selector, address(_getV2CoreContract(markets[i], feeds[j])), true
          )
        );

        _call(
          address(ethPMRM),
          abi.encodeWithSelector(
            srm.setWhitelistedCallee.selector, address(_getV2CoreContract(markets[i], feeds[j])), true
          )
        );
      }

      /////
      // Adjust cap

      (uint perpCap,,) = Config.getSRMCaps(markets[i]);

      _call(
        address(_getV2CoreContract(markets[i], "perp")),
        abi.encodeWithSelector(PositionTracking.setTotalPositionCap.selector, IManager(srm), perpCap)
      );

      //////
      // Add to modules

      for (uint j = 0; j < modules.length; j++) {
        _call(
          _getMatchingContract("matching", modules[j]),
          abi.encodeWithSelector(
            TradeModule.setPerpAsset.selector, IPerpAsset(_getV2CoreContract(markets[i], "perp")), true
          )
        );
      }
    }
  }
}
