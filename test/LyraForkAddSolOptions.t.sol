pragma solidity ^0.8.20;

import "./ForkBase.t.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "openzeppelin/access/Ownable2Step.sol";
import "v2-core/scripts/config-mainnet.sol";
import "v2-core/scripts/types.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/test/shared/mocks/MockFeeds.sol";
import {LyraERC20} from "v2-core/src/l2/LyraERC20.sol";

contract LyraForkAddSolOptionsTest is ForkBase {
  struct Market {
    LyraSpotFeed spotFeed;
    LyraForwardFeed forwardFeed;
    LyraVolFeed volFeed;
    OptionAsset option;
    WrappedERC20Asset base;
  }
  //
  //  address alice = address(1);
  //  address bob = address(2);
  //  address owner = address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);
  //
  //  uint currentSpot = 250e18;
  //  uint128[] strikes = [400e18, 600e18, 800e18, 1000e18, 1500e18, 2000e18];
  //  uint64[2] expiries = [1738310400, 1743148800];
  //
  //  function setUp() external {}
  //
  //  function testFork() external checkFork {
  //    vm.deal(owner, 1 ether);
  //    vm.startPrank(owner);
  //
  //
  //    StandardManager srm = StandardManager(_getV2CoreContract("core", "srm"));
  //    SubAccounts subAcc = SubAccounts(_getV2CoreContract("core", "subAccounts"));
  //
  //    Market memory market;
  //
  //    MockFeeds feeds = new MockFeeds();
  //
  //    market.option = new OptionAsset(
  //      subAcc, address(market.forwardFeed)
  //    );
  //
  //    market.option.setWhitelistManager(address(srm), true);
  //    market.option.setTotalPositionCap(srm, 1000000e18);
  //
  //    ///
  //    uint marketId = 7;
  //    (,,IStandardManager.OracleContingencyParams memory oracleContingencyParams,) = Config.getSRMParams("SOL");
  //
  //    IStandardManager.OptionMarginParams memory optionMarginParams = IStandardManager.OptionMarginParams({
  //      /// @dev Percentage of spot to add to initial margin if option is ITM. Decreases as option becomes more OTM.
  //      maxSpotReq: 0.15e18,
  //      /// @dev Minimum amount of spot price to add as initial margin.
  //      minSpotReq: 0.13e18,
  //      /// @dev Minimum amount of spot price to add as maintenance margin.
  //      mmCallSpotReq: 0.09e18,
  //      /// @dev Minimum amount of spot to add for maintenance margin
  //      mmPutSpotReq: 0.09e18,
  //      /// @dev Minimum amount of mtm to add for maintenance margin for puts
  //      MMPutMtMReq: 0.09e18,
  //      /// @dev Scaler applied to forward by amount if max loss is unbounded, when calculating IM
  //      unpairedIMScale: 1.2e18,
  //      /// @dev Scaler applied to forward by amount if max loss is unbounded, when calculating MM
  //      unpairedMMScale: 1.1e18,
  //      /// @dev Scale the MM for a put as minimum of IM
  //      mmOffsetScale: 1.05e18
  //    });
  //
  //    // set assets per market
  //    srm.whitelistAsset(market.option, marketId, IStandardManager.AssetType.Option);
  //
  //    // set oracles
  //    srm.setOraclesForMarket(marketId, feeds, feeds, feeds);
  //
  //    // set params
  //    srm.setOptionMarginParams(marketId, optionMarginParams);
  //
  //    srm.setOracleContingencyParams(marketId, oracleContingencyParams);
  //
  //    ////////////////////////////////
  //    // Set feeds and trade option //
  //    ////////////////////////////////
  //
  //
  //    LyraERC20 usdc = LyraERC20(_getV2CoreContract("shared", "usdc"));
  //    _getV2CoreContract("shared", "usdc").call(abi.encodeWithSignature("configureMinter(address,uint256)", address(owner), 1000000e6));
  //    usdc.mint(address(owner), 1000000e6);
  //    usdc.approve(address(_getV2CoreContract("core", "cash")), 1000000e6);
  //    uint sub1 = subAcc.createAccount(address(owner), srm);
  //    uint sub2 = subAcc.createAccount(address(owner), srm);
  //
  //    CashAsset cash = CashAsset(_getV2CoreContract("core", "cash"));
  //    cash.deposit(sub1, 50000e6);
  //    cash.deposit(sub2, 50000e6);
  //
  //    /////////////////////
  //    // Params for test //
  //    /////////////////////
  //
  //
  //    feeds.setSpot(currentSpot, 1e18);
  //
  //    for (uint i = 0; i < expiries.length; i++) {
  //      console.log();
  //      console.log("expiry", expiries[i]);
  //
  //      for (uint j = 0; j < strikes.length; j++) {
  //        uint256 snapshot = vm.snapshotState();
  //
  //        feeds.setForwardPrice(expiries[i], currentSpot, 1e18);
  //        feeds.setVol(expiries[i], strikes[j], 1.1e18, 1e18);
  //
  //        subAcc.submitTransfer(ISubAccounts.AssetTransfer({
  //          fromAcc: sub1,
  //          toAcc: sub2,
  //          asset: market.option,
  //          subId: OptionEncoding.toSubId(expiries[i], strikes[j], true),
  //          amount: 1e18,
  //          assetData: ""
  //        }), "");
  //
  //        int margin = srm.getMargin(sub1, true);
  //
  //        (, bytes memory x) = 0x8574CBC539c26Df9ec11bA283218268101ff10e1.call(abi.encodeWithSelector(bytes4(hex"e31d0acb"), [expiries[i] - block.timestamp, 1e18, 1.1e18, currentSpot, strikes[j]]));
  //        (int call,) = abi.decode(x, (int, int));
  //
  //        console.log();
  //        console.log("strike", strikes[j] / 1e18);
  //        console.log("call", call);
  //        console.log("margin for call", margin + call - 50000e18);
  //
  //        vm.revertToState(snapshot);
  //      }
  //    }
  //
  //  }
}
