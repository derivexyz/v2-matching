pragma solidity 0.8.20;

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

contract LyraForkTest is ForkBase {
  string[1] public MARKETS = ["TRUMP"];
  string[4] public feeds = ["spotFeed", "perpFeed", "iapFeed", "ibpFeed"];

  uint[2][] public MARKET_PARAMS = [[0.1e18, 0.15e18]];

  function setUp() external {}

  function testFork() external checkFork {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getV2CoreContract(_readV2CoreDeploymentFile("core"), "srm"));

    PMRM ethPMRM = PMRM(_getV2CoreContract("ETH", "pmrm"));
    PMRM btcPMRM = PMRM(_getV2CoreContract("BTC", "pmrm"));

    for (uint i = 0; i < MARKETS.length; i++) {
      string memory market = MARKETS[i];
      console.log("market:", market);
      string memory deploymentFile = _readV2CoreDeploymentFile(market);

      uint marketId = srm.createMarket(market);
      console.log("marketId:", marketId);

      srm.setOracleContingencyParams(
        marketId,
        IStandardManager.OracleContingencyParams({
          perpThreshold: 0.55e18,
          optionThreshold: 0.55e18,
          baseThreshold: 0.55e18,
          OCFactor: 1e18
        })
      );

      srm.setPerpMarginRequirements(marketId, 0.6e18, 0.8e18);
      srm.setOraclesForMarket(
        marketId,
        ISpotFeed(_getV2CoreContract(deploymentFile, "spotFeed")),
        IForwardFeed(address(0)),
        IVolFeed(address(0))
      );

      srm.whitelistAsset(
        IAsset(_getV2CoreContract(deploymentFile, "perp")), marketId, IStandardManager.AssetType.Perpetual
      );

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getV2CoreContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getV2CoreContract(deploymentFile, "perp"), 0.5e18);
      //      TradeModule(_getV2CoreContract(deploymentFile, "tradeModule")).setPerpAsset(_getV2CoreContract(deploymentFile, "perp"), true);

      for (uint j = 0; j < feeds.length; j++) {
        string memory feed = feeds[j];
        console.log("feed:", feed);
        srm.setWhitelistedCallee(_getV2CoreContract(deploymentFile, feed), true);
        ethPMRM.setWhitelistedCallee(_getV2CoreContract(deploymentFile, feed), true);
        btcPMRM.setWhitelistedCallee(_getV2CoreContract(deploymentFile, feed), true);
      }

      Ownable2Step(_getV2CoreContract(deploymentFile, "perp")).acceptOwnership();
      Ownable2Step(_getV2CoreContract(deploymentFile, "spotFeed")).acceptOwnership();
      Ownable2Step(_getV2CoreContract(deploymentFile, "perpFeed")).acceptOwnership();
      Ownable2Step(_getV2CoreContract(deploymentFile, "iapFeed")).acceptOwnership();
      Ownable2Step(_getV2CoreContract(deploymentFile, "ibpFeed")).acceptOwnership();

      TradeModule(_getMatchingContract("matching", "trade")).setPerpAsset(
        IPerpAsset(_getV2CoreContract(deploymentFile, "perp")), true
      );
      TradeModule(_getMatchingContract("matching", "rfq")).setPerpAsset(
        IPerpAsset(_getV2CoreContract(deploymentFile, "perp")), true
      );
      //      TradeModule(_getMatchingContract("matching", "liquidate")).setPerpAsset(IPerpAsset(_getV2CoreContract(deploymentFile, "perp")), true);
    }
  }
}
