// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import {IntegrationTestBase} from "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";

import "forge-std/console2.sol";
import "../../src/periphery/LyraAuctionUtils.sol";

contract LyraAuctionUtilsTest is IntegrationTestBase {
  LyraAuctionUtils public auctionUtils;

  function setUp() public {
    _setupIntegrationTestComplete();

    auctionUtils = new LyraAuctionUtils(subAccounts, auction, address(srm));
  }

  function testCanLiquidateViaAuctionUtils() public {
    // allow opening just above MM
    markets["weth"].pmrm.setTrustedRiskAssessor(address(this), true);

    uint64 expiry = uint64(block.timestamp + 1 weeks);
    uint strike = 1000e18;

    _setSpotPrice("weth", 1500e18, 1e18);
    _setForwardPrice("weth", expiry, 1500e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);

    usdc.mint(address(this), 1e18);
    usdc.approve(address(cash), 1e18);

    uint subA = subAccounts.createAccountWithApproval(alice, address(this), IManager(address(markets["weth"].pmrm)));
    uint liquidatorAcc = subAccounts.createAccountWithApproval(bob, address(this), IManager(address(srm)));

    cash.deposit(subA, 7000e6);
    cash.deposit(liquidatorAcc, 10000e6);

    _transferOption(subA, bobAcc, 10e18, expiry, strike, false);

    (address manager, int mm, int mtm, uint worstScenario) = auctionUtils.getMM(subA);
    assertGt(mm, 0);
    assertEq(manager, address(markets["weth"].pmrm));
    (manager, mm, mtm, worstScenario) = auctionUtils.getMM(bobAcc);
    assertEq(manager, address(srm));

    _setForwardPrice("weth", expiry, 1000e18, 1e18);
    (manager, mm, mtm, worstScenario) = auctionUtils.getMM(subA);
    assertEq(worstScenario, 18);

    vm.startPrank(bob);
    subAccounts.approve(address(auctionUtils), liquidatorAcc);

    // mm == -550, mtm == 2200 -> bm == (-550 - 2200) * 0.3 + -550 = -1375
    // bid price == 1 (starting %) * 2200 == 2200
    // required collateral = 580 + 1375 ~= 1950

    // cannot bid without sending cash to the new account
    vm.expectRevert(IDutchAuction.DA_InvalidBidderPortfolio.selector);
    auctionUtils.advancedBid(worstScenario, subA, liquidatorAcc, 0.01e18, 0, 0, 0, true, "");

    // Need to send enough
    vm.expectRevert(IDutchAuction.DA_InsufficientCash.selector);
    auctionUtils.advancedBid(worstScenario, subA, liquidatorAcc, 0.01e18, 0, 0, 19e18, true, "");

    // Liquidator starts with only cash
    assertEq(subAccounts.getUniqueAssets(liquidatorAcc).length, 1);
    uint newSubId = auctionUtils.advancedBid(worstScenario, subA, liquidatorAcc, 0.01e18, 0, 0, 100e18, true, "");
    // new subid has no balances as it was merged
    assertEq(subAccounts.getUniqueAssets(newSubId).length, 0);
    // has short option merged into their account
    assertEq(subAccounts.getUniqueAssets(liquidatorAcc).length, 2);

    newSubId = auctionUtils.advancedBid(worstScenario, subA, liquidatorAcc, 0.01e18, 0, 0, 100e18, false, "");
    // new subaccount created with cash and option
    assertEq(subAccounts.getUniqueAssets(newSubId).length, 2);
  }

  function _transferOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: markets["weth"].option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }
}
