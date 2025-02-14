pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "v2-core/scripts/types.sol";
import "forge-std/console2.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./ForkBase.t.sol";
import {LyraERC20} from "v2-core/src/l2/LyraERC20.sol";

contract LyraForkSRMUpgradeTest is ForkBase {
  function setUp() external {}

  function testFork() external checkFork {
    WrappedERC20Asset wethAsset = WrappedERC20Asset(_getV2CoreContract("ETH", "base"));
    LyraERC20 weth = LyraERC20(address(wethAsset.wrappedAsset()));
    StandardManager srm = StandardManager(_getV2CoreContract("core", "srm"));

    if (block.chainid == 957) {
      vm.deal(weth.owner(), 1 ether);
      vm.startPrank(weth.owner());
      weth.configureMinter(srm.owner(), true);
      vm.stopPrank();
    }

    vm.deal(srm.owner(), 1 ether);
    vm.startPrank(srm.owner());
    srm.setBaseAssetMarginFactor(1, 0.5e18, 1e18);
    weth.mint(address(this), 1e18);
    vm.stopPrank();

    uint newSubaccount = SubAccounts(_getV2CoreContract("core", "subAccounts")).createAccount(address(srm.owner()), srm);

    weth.approve(address(wethAsset), 1e18);
    wethAsset.deposit(newSubaccount, 1e18);

    CashAsset cash = CashAsset(_getV2CoreContract("core", "cash"));

    vm.startPrank(srm.owner());
    cash.withdraw(newSubaccount, 200e6, address(this));

    vm.expectRevert(IStandardManager.SRM_PortfolioBelowMargin.selector);
    wethAsset.withdraw(newSubaccount, uint(1e18), address(this));
    vm.stopPrank();
  }
}
