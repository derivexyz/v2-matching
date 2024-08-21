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

  function testFork() external {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getContract("core", "srm"));

    {
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
        marketId, ISpotFeed(_getContract("DAI", "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
      );

      srm.whitelistAsset(IAsset(_getContract("DAI", "base")), marketId, IStandardManager.AssetType.Base);

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getContract("core", "srmViewer"));
      srmViewer.setOIFeeRateBPS(_getContract("DAI", "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract("DAI", "spotFeed"), true);
      PMRM(_getContract("ETH", "pmrm")).setWhitelistedCallee(_getContract("DAI", "spotFeed"), true);
      PMRM(_getContract("BTC", "pmrm")).setWhitelistedCallee(_getContract("DAI", "spotFeed"), true);

      Ownable2Step(_getContract("DAI", "base")).acceptOwnership();
      Ownable2Step(_getContract("DAI", "spotFeed")).acceptOwnership();
    }
    {
      uint marketId = srm.createMarket("sDAI");
      console.log("marketId:", marketId);

      srm.whitelistAsset(IAsset(_getContract("sDAI", "base")), marketId, IStandardManager.AssetType.Base);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract("sDAI", "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
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
      srmViewer.setOIFeeRateBPS(_getContract("sDAI", "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract("sDAI", "spotFeed"), true);
      PMRM(_getContract("ETH", "pmrm")).setWhitelistedCallee(_getContract("sDAI", "spotFeed"), true);
      PMRM(_getContract("BTC", "pmrm")).setWhitelistedCallee(_getContract("sDAI", "spotFeed"), true);

      Ownable2Step(_getContract("sDAI", "base")).acceptOwnership();
      Ownable2Step(_getContract("sDAI", "spotFeed")).acceptOwnership();
    }
    {
      uint marketId = srm.createMarket("USDe");
      console.log("marketId:", marketId);

      srm.whitelistAsset(IAsset(_getContract("USDe", "base")), marketId, IStandardManager.AssetType.Base);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract("USDe", "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
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
      srmViewer.setOIFeeRateBPS(_getContract("USDe", "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract("USDe", "spotFeed"), true);
      PMRM(_getContract("ETH", "pmrm")).setWhitelistedCallee(_getContract("USDe", "spotFeed"), true);
      PMRM(_getContract("BTC", "pmrm")).setWhitelistedCallee(_getContract("USDe", "spotFeed"), true);

      Ownable2Step(_getContract("USDe", "base")).acceptOwnership();
      Ownable2Step(_getContract("USDe", "spotFeed")).acceptOwnership();
    }
    {
      uint marketId = srm.createMarket("PYUSD");
      console.log("marketId:", marketId);

      srm.whitelistAsset(IAsset(_getContract("PYUSD", "base")), marketId, IStandardManager.AssetType.Base);
      srm.setOraclesForMarket(
        marketId, ISpotFeed(_getContract("PYUSD", "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0))
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
      srmViewer.setOIFeeRateBPS(_getContract("PYUSD", "base"), 0.5e18);

      srm.setWhitelistedCallee(_getContract("PYUSD", "spotFeed"), true);
      PMRM(_getContract("ETH", "pmrm")).setWhitelistedCallee(_getContract("PYUSD", "spotFeed"), true);
      PMRM(_getContract("BTC", "pmrm")).setWhitelistedCallee(_getContract("PYUSD", "spotFeed"), true);

      Ownable2Step(_getContract("PYUSD", "base")).acceptOwnership();
      Ownable2Step(_getContract("PYUSD", "spotFeed")).acceptOwnership();
      WrappedERC20Asset(_getContract("PYUSD", "base")).setTotalPositionCap(srm, 0);
    }
  }

  function _getContract(string memory file, string memory name) internal view returns (address) {
    file = _readDeploymentFile(file);
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
