pragma solidity 0.8.20;

import "forge-std/console.sol";
import "v2-core/scripts/types.sol";
import "forge-std/console2.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./fork/ForkBase.t.sol";
import "v2-core/scripts/config-mainnet.sol";

contract PerpMarketFork is ForkBase {
  string[10] public MARKETS = ["LINK", "XRP", "AVAX", "UNI", "TAO", "SEI", "EIGEN", "ENA", "BITCOIN", "DEGEN"];
  string[4] public feeds = ["spotFeed", "perpFeed", "iapFeed", "ibpFeed"];

  /**
   * [COIN, IM leverage, MM leverage, OI cap]
   * LINK,   10x,        15x,         50K
   * XRP,    10x,        15x,         1M
   * AVAX,   10x,        15x,         20K
   * UNI,    10x,        15x,         60K
   * TAO     5x,         15x,         1K
   * SEI,    5x,         15x,         1M
   * EIGEN,  5x,         15x,         150K
   * ENA     10k,        15k,         1M
   * BITCOIN,3k,         5k,          600k
   * DEGEN,  3k,         5k,          20M
   */
  function setUp() external {}

  function testFork() external skipped {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(0x28c9ddF9A3B29c2E6a561c1BC520954e5A33de5D);

    PMRM ethPMRM = PMRM(0xe7cD9370CdE6C9b5eAbCe8f86d01822d3de205A0);
    PMRM btcPMRM = PMRM(0x45DA02B9cCF384d7DbDD7b2b13e705BADB43Db0D);

    for (uint i = 0; i < MARKETS.length; i++) {
      string memory market = MARKETS[i];
      console.log("market:", market);
      string memory deploymentFile = _readV2CoreDeploymentFile(market);

      uint marketId = srm.createMarket(market);
      console.log("marketId:", marketId);

      (
        IStandardManager.PerpMarginRequirements memory perpMarginRequirements,
        ,
        IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      ) = Config.getSRMParams(market);

      srm.setOracleContingencyParams(marketId, oracleContingencyParams);

      srm.setPerpMarginRequirements(marketId, perpMarginRequirements.mmPerpReq, perpMarginRequirements.imPerpReq);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract(deploymentFile, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.whitelistAsset(IAsset(_getContract(deploymentFile, "perp")), marketId, IStandardManager.AssetType.Perpetual);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getV2CoreContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract(deploymentFile, "perp"), 0.1e18);

      for (uint j = 0; j < feeds.length; j++) {
        string memory feed = feeds[j];
        console.log("feed:", feed);
        srm.setWhitelistedCallee(_getContract(deploymentFile, feed), true);
        ethPMRM.setWhitelistedCallee(_getContract(deploymentFile, feed), true);
        btcPMRM.setWhitelistedCallee(_getContract(deploymentFile, feed), true);
      }

      Ownable2Step(_getContract(deploymentFile, "perp")).acceptOwnership();
      Ownable2Step(_getContract(deploymentFile, "spotFeed")).acceptOwnership();
      Ownable2Step(_getContract(deploymentFile, "perpFeed")).acceptOwnership();
      Ownable2Step(_getContract(deploymentFile, "iapFeed")).acceptOwnership();
      Ownable2Step(_getContract(deploymentFile, "ibpFeed")).acceptOwnership();
    }
  }
}
