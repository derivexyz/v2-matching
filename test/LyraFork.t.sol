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
  function setUp() external {}

  function testFork() external skipped {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getContract(_readV2CoreDeploymentFile("core"), "srm"));

    {
      string memory market = "DAI";
      uint marketId = srm.createMarket("DAI");
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

      srm.setPerpMarginRequirements(marketId, 0.8e18, 0.6e18);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract(dai_deployment, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.whitelistAsset(IAsset(_getContract(dai_deployment, "base")), marketId, IStandardManager.AssetType.Base);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getContract(_readV2CoreDeploymentFile("core"), "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract(dai_deployment, "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract(dai_deployment, "spotFeed"), true);
      PMRM(_getContract(eth_deployment, "pmrm")).setWhitelistedCallee(_getContract(dai_deployment, "spotFeed"), true);
      PMRM(_getContract(btc_deployment, "pmrm")).setWhitelistedCallee(_getContract(dai_deployment, "spotFeed"), true);

      Ownable2Step(_getContract(dai_deployment, "base")).acceptOwnership();
      Ownable2Step(_getContract(dai_deployment, "spotFeed")).acceptOwnership();
    }
  }
}
