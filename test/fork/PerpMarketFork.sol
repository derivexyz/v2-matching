pragma solidity 0.8.20;

import "forge-std/console.sol";
import "v2-core/scripts/types.sol";
import "forge-std/console2.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./ForkBase.t.sol";
import "v2-core/scripts/config-mainnet.sol";

contract PerpMarketFork is ForkBase {
  struct CD {
    address addr;
    bytes data;
  }

  string[10] public MARKETS = ["LINK", "XRP", "AVAX", "UNI", "TAO", "SEI", "EIGEN", "ENA", "BITCOIN", "DEGEN"];
  string[4] public feeds = ["spotFeed", "perpFeed", "iapFeed", "ibpFeed"];

  CD[] public calldatas;

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
   * BITCOIN,3x,         5x,          600k
   * DEGEN,  3x,         5x,          20M
   */
  function setUp() external {}

  function testFork() external {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(0x28c9ddF9A3B29c2E6a561c1BC520954e5A33de5D);

    PMRM ethPMRM = PMRM(0xe7cD9370CdE6C9b5eAbCe8f86d01822d3de205A0);
    PMRM btcPMRM = PMRM(0x45DA02B9cCF384d7DbDD7b2b13e705BADB43Db0D);

    // store every function calldata as a pair of (address, calldata) in a string array

    for (uint i = 0; i < MARKETS.length; i++) {
      string memory market = MARKETS[i];
      console.log("market:", market);
      string memory deploymentFile = _readV2CoreDeploymentFile(market);

      uint marketId = srm.createMarket(market);
      calldatas.push(CD(address(srm), abi.encodeWithSelector(srm.createMarket.selector, market)));

      console.log("marketId:", marketId);
      (
        IStandardManager.PerpMarginRequirements memory perpMarginRequirements,
        ,
        IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      ) = Config.getSRMParams(market);

      calldatas.push(_call(address(srm), abi.encodeWithSelector(srm.setOracleContingencyParams.selector, marketId, oracleContingencyParams)));
      calldatas.push(_call(address(srm), abi.encodeWithSelector(srm.setPerpMarginRequirements.selector, marketId, perpMarginRequirements.mmPerpReq, perpMarginRequirements.imPerpReq)));
      calldatas.push(_call(address(srm), abi.encodeWithSelector(srm.setOraclesForMarket.selector, marketId, ISpotFeed(_getContract(deploymentFile, "spotFeed")), IForwardFeed(address(0)), IVolFeed(address(0)))));
      calldatas.push(_call(address(srm), abi.encodeWithSelector(srm.whitelistAsset.selector, IAsset(_getContract(deploymentFile, "perp")), marketId, IStandardManager.AssetType.Perpetual)));

      SRMPortfolioViewer srmViewer = SRMPortfolioViewer(_getV2CoreContract("core", "srmViewer"));
      calldatas.push(_call(address(srmViewer), abi.encodeWithSelector(srmViewer.setOIFeeRateBPS.selector, _getContract(deploymentFile, "perp"), 0.5e18)));

      for (uint j = 0; j < feeds.length; j++) {
        string memory feed = feeds[j];
        console.log("feed:", feed);
        calldatas.push(_call(address(srm), abi.encodeWithSelector(srm.setWhitelistedCallee.selector, _getContract(deploymentFile, feed), true)));
        calldatas.push(_call(address(ethPMRM), abi.encodeWithSelector(ethPMRM.setWhitelistedCallee.selector, _getContract(deploymentFile, feed), true)));
        calldatas.push(_call(address(btcPMRM), abi.encodeWithSelector(btcPMRM.setWhitelistedCallee.selector, _getContract(deploymentFile, feed), true)));
      }

      calldatas.push(_call(_getContract(deploymentFile, "perp"), abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)));
      calldatas.push(_call(_getContract(deploymentFile, "spotFeed"), abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)));
      calldatas.push(_call(_getContract(deploymentFile, "perpFeed"), abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)));
      calldatas.push(_call(_getContract(deploymentFile, "iapFeed"), abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)));
      calldatas.push(_call(_getContract(deploymentFile, "ibpFeed"), abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector)));
    }

    //print all the function calldata
    uint txsPerMarket = calldatas.length / MARKETS.length;
    for (uint i = 0; i < txsPerMarket; i++) {
      for (uint j = 0; j < MARKETS.length; j++) {
        console.log(calldatas[j * txsPerMarket + i].addr, ",");
        console.logBytes(calldatas[j * txsPerMarket + i].data);
      }
    }
  }

  function _call(address addr, bytes memory data) internal returns (CD memory) {
    (bool success, bytes memory ret) = addr.call(data);
    require(success, string(ret));
    return CD(addr, data);
  }
}
