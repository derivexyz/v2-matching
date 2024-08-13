pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "v2-core/scripts/types.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";



contract LyraForkTest is Test {
  function setUp() external {}

  function testFork() external {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getContract("core", "srm"));

    uint marketId = srm.createMarket("sUSDe");
    console.log("marketId:", marketId);

    srm.whitelistAsset(IAsset(_getContract("sUSDe", "base")), marketId, IStandardManager.AssetType.Base);
    srm.setOraclesForMarket(marketId, ISpotFeed(_getContract("sUSDe", "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0)));

    srm.setOracleContingencyParams(marketId, IStandardManager.OracleContingencyParams({
      perpThreshold: 0.55e18,
      optionThreshold: 0.55e18,
      baseThreshold: 0.55e18,
      OCFactor: 1e18
    }));

    srm.setBaseAssetMarginFactor(marketId, 0.8e18, 0.6e18);

    SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getContract("core", "srmViewer"));
    srmViewer.setOIFeeRateBPS(_getContract("sUSDe", "base"), 0.5e18);

    srm.setWhitelistedCallee(_getContract("sUSDe", "spotFeed"), true);
    PMRM(_getContract("ETH", "pmrm")).setWhitelistedCallee(_getContract("sUSDe", "spotFeed"), true);
    PMRM(_getContract("BTC", "pmrm")).setWhitelistedCallee(_getContract("sUSDe", "spotFeed"), true);

    Ownable2Step(_getContract("sUSDe", "base")).acceptOwnership();
    Ownable2Step(_getContract("sUSDe", "spotFeed")).acceptOwnership();
  }

  function _getContract(string memory file, string memory name) internal view returns (address) {
    string memory file = _readDeploymentFile(file);
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
