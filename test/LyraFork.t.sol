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
      string memory dai_deployment = _readV2CoreDeploymentFile("DAI");
      string memory eth_deployment = _readV2CoreDeploymentFile("ETH");
      string memory btc_deployment = _readV2CoreDeploymentFile("BTC");
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

      srm.setBaseAssetMarginFactor(marketId, 0.8e18, 0.6e18);
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
    {
      string memory sdai_deployment = _readV2CoreDeploymentFile("sDAI");
      string memory eth_deployment = _readV2CoreDeploymentFile("ETH");
      string memory btc_deployment = _readV2CoreDeploymentFile("BTC");
      uint marketId = srm.createMarket("sDAI");
      console.log("marketId:", marketId);

      srm.whitelistAsset(IAsset(_getContract(sdai_deployment, "base")), marketId, IStandardManager.AssetType.Base);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract(sdai_deployment, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.setOracleContingencyParams(
        marketId,
        IStandardManager.OracleContingencyParams({
          perpThreshold: 0.55e18,
          optionThreshold: 0.55e18,
          baseThreshold: 0.55e18,
          OCFactor: 1e18
        })
      );

      srm.setBaseAssetMarginFactor(marketId, 0.8e18, 0.6e18);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract(sdai_deployment, "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract(sdai_deployment, "spotFeed"), true);
      PMRM(_getContract(eth_deployment, "pmrm")).setWhitelistedCallee(_getContract(sdai_deployment, "spotFeed"), true);
      PMRM(_getContract(btc_deployment, "pmrm")).setWhitelistedCallee(_getContract(sdai_deployment, "spotFeed"), true);

      Ownable2Step(_getContract(sdai_deployment, "base")).acceptOwnership();
      Ownable2Step(_getContract(sdai_deployment, "spotFeed")).acceptOwnership();
    }
    {
      string memory usde_deployment = _readV2CoreDeploymentFile("USDe");
      string memory eth_deployment = _readV2CoreDeploymentFile("ETH");
      string memory btc_deployment = _readV2CoreDeploymentFile("BTC");
      uint marketId = srm.createMarket("USDe");
      console.log("marketId:", marketId);

      srm.whitelistAsset(IAsset(_getContract(usde_deployment, "base")), marketId, IStandardManager.AssetType.Base);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract(usde_deployment, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.setOracleContingencyParams(
        marketId,
        IStandardManager.OracleContingencyParams({
          perpThreshold: 0.55e18,
          optionThreshold: 0.55e18,
          baseThreshold: 0.55e18,
          OCFactor: 1e18
        })
      );

      srm.setBaseAssetMarginFactor(marketId, 0.8e18, 0.6e18);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract(usde_deployment, "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract(usde_deployment, "spotFeed"), true);
      PMRM(_getContract(eth_deployment, "pmrm")).setWhitelistedCallee(_getContract(usde_deployment, "spotFeed"), true);
      PMRM(_getContract(btc_deployment, "pmrm")).setWhitelistedCallee(_getContract(usde_deployment, "spotFeed"), true);

      Ownable2Step(_getContract(usde_deployment, "base")).acceptOwnership();
      Ownable2Step(_getContract(usde_deployment, "spotFeed")).acceptOwnership();
    }
    {
      string memory pyusd_deployment = _readV2CoreDeploymentFile("PYUSD");
      string memory eth_deployment = _readV2CoreDeploymentFile("ETH");
      string memory btc_deployment = _readV2CoreDeploymentFile("BTC");
      uint marketId = srm.createMarket("PYUSD");
      console.log("marketId:", marketId);

      srm.whitelistAsset(IAsset(_getContract(pyusd_deployment, "base")), marketId, IStandardManager.AssetType.Base);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract(pyusd_deployment, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.setOracleContingencyParams(
        marketId,
        IStandardManager.OracleContingencyParams({
          perpThreshold: 0.55e18,
          optionThreshold: 0.55e18,
          baseThreshold: 0.55e18,
          OCFactor: 1e18
        })
      );

      srm.setBaseAssetMarginFactor(marketId, 0.8e18, 0.6e18);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract(pyusd_deployment, "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract(pyusd_deployment, "spotFeed"), true);
      PMRM(_getContract(eth_deployment, "pmrm")).setWhitelistedCallee(_getContract(pyusd_deployment, "spotFeed"), true);
      PMRM(_getContract(btc_deployment, "pmrm")).setWhitelistedCallee(_getContract(pyusd_deployment, "spotFeed"), true);

      Ownable2Step(_getContract(pyusd_deployment, "base")).acceptOwnership();
      Ownable2Step(_getContract(pyusd_deployment, "spotFeed")).acceptOwnership();
      WrappedERC20Asset(_getContract(pyusd_deployment, "base")).setTotalPositionCap(srm, 0);
    }
  }
}
