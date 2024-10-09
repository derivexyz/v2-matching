pragma solidity 0.8.20;

import "forge-std/console.sol";
import "v2-core/scripts/types.sol";
import "forge-std/console2.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./ForkBase.t.sol";

contract LyraForkTest is ForkBase {
  string[10] public MARKETS = ["TIA", "SUI", "NEAR", "PEPE", "WIF", "WLD", "BNB", "AAVE", "OP", "ARB"];
  string[4] public feeds = ["spotFeed", "perpFeed", "iapFeed", "ibpFeed"];

  // SOL (update)	10x 	15x	Leave as is 	Leave as is
  //DOGE (update)	10x    	15x	5M DOGE	$500K
  //TIA	10x	15x	100K TIA	$500K
  //SUI	10x 	15x	250K SUI	$500K
  //NEAR	10x 	15x 	40K NEAR	$200K
  //(M)PEPE	5x 	7x 	20K MPEPE	$200K
  //WIF	5x 	7x 	100K WIF 	$200K
  //Worldcoin	10x 	15x 	100K WLD	$200K
  //BNB	10x 	15x	800 BNB	$500K
  //Aave	10x 	15x	3K Aave	$500K
  //OP	10x 	15x	250K OP	$500K
  //ARB	10x 	15x	750K ARB	$500K

  uint[2][] public MARKET_PARAMS = [[0.1e18, 0.15e18]];

  function setUp() external {}

  function testFork() external skipped {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getContract(_readV2CoreDeploymentFile("core"), "srm"));

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
        marketId, ISpotFeed(_getContract(deploymentFile, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.whitelistAsset(IAsset(_getContract(deploymentFile, "perp")), marketId, IStandardManager.AssetType.Perpetual);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getV2CoreContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract(deploymentFile, "perp"), 0.5e18);

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
