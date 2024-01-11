// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {ILiquidateModule} from "src/interfaces/ILiquidateModule.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {MockDataReceiver} from "../mock/MockDataReceiver.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IBaseModule} from "src/interfaces/IBaseModule.sol";

import "forge-std/console2.sol";

contract LiquidationModuleTest is MatchingBase {
  event LiquidationPerpPrice(address perp, uint perpPrice, uint confidence);

  // Test liquidations
  // - Liquidate partially
  // - Liquidates fully, merging
  // - Liquidates fully, creating new subaccount
  // - Liquidates insolvent auction
  // - can submit feed data
  // - Reverts in different cases
  //  - cannot resubmit same signed message/nonce
  //  - not enough cash transferred
  //  - invalid lastTradeId
  //  - min/max bid price for solvent/insolvent

  uint public liqAcc;

  function setUp() public override {
    super.setUp();

    // create an account that is in auction
    liqAcc = subAccounts.createAccount(address(this), IManager(address(pmrm)));
    uint traderAcc = subAccounts.createAccount(address(this), IManager(address(pmrm)));
    _depositCash(liqAcc, 1000e18);
    _depositCash(traderAcc, 1000e18);

    ISubAccounts.AssetBalance[] memory trade = new ISubAccounts.AssetBalance[](1);
    trade[0] = ISubAccounts.AssetBalance({asset: mockPerp, subId: 0, balance: 1e18});
    _doBalanceTransfer(traderAcc, liqAcc, trade);

    mockPerp.setMockPerpPrice(7000e18, 1e18);
    auction.startAuction(liqAcc, 20);
  }

  function testPartialSolventAuction() public {
    _bidOnAuction(1000e18, 0.1e18, 0, 0, true);

    assertEq((auction.getAuction(liqAcc)).ongoing, true);
    assertEq(subAccounts.getBalance(camAcc, mockPerp, 0), 0.1e18);
  }

  function testFullSolventAuction() public {
    _bidOnAuction(1000e18, 1e18, 0, 0, true);

    assertEq((auction.getAuction(liqAcc)).ongoing, false);
    assertGt(subAccounts.getBalance(camAcc, mockPerp, 0), 0.2e18);
    assertEq(subAccounts.getBalance(camAcc, mockPerp, 0) + subAccounts.getBalance(liqAcc, mockPerp, 0), 1e18);
  }

  function testFullSolventAuctionNoMerge() public {
    _bidOnAuction(1000e18, 1e18, 0, 0, false);

    assertEq((auction.getAuction(liqAcc)).ongoing, false);
    // new subaccount created for cam, id: 14
    assertGt(subAccounts.getBalance(10, mockPerp, 0), 0.2e18);
    assertEq(subAccounts.getBalance(10, mockPerp, 0) + subAccounts.getBalance(liqAcc, mockPerp, 0), 1e18);
    assertEq(subAccounts.ownerOf(10), address(matching));
    assertEq(matching.subAccountToOwner(10), cam);
  }

  function testInsolventAuction() public {
    vm.warp(block.timestamp + 2 days);
    auction.convertToInsolventAuction(liqAcc);
    assertEq((auction.getAuction(liqAcc)).insolvent, true);

    _bidOnAuction(1000e18, 1e18, 0, 0, true);

    assertEq((auction.getAuction(liqAcc)).ongoing, false);
    assertEq(subAccounts.getBalance(camAcc, mockPerp, 0), 1e18);
    assertEq(subAccounts.getBalance(liqAcc, mockPerp, 0), 0);
  }

  function testCanSubmitFeedDataWithBid() public {
    IBaseManager.ManagerData[] memory data = new IBaseManager.ManagerData[](1);
    data[0] = IBaseManager.ManagerData({receiver: bob, data: ""});

    (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) =
      _getBidActionData(1000e18, 1e18, 0, 0, true, abi.encode(data));

    // Easiest way to test that the call to the receiver happened, since tests aren't setup to support full feeds
    vm.expectRevert(IBaseManager.BM_UnauthorizedCall.selector);
    _verifyAndMatch(actions, signatures, actionData);
  }

  function testLiquidationEmitPerpPrice() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: baseAsset, subId: 0, balance: 0.05e18});
    setBalances(liqAcc, balances);

    vm.expectEmit(true, false, false, true, address(liquidateModule)); // topic0, topic1, topic2, checkData, emitter
    // We emit the event we expect to see.
    emit LiquidationPerpPrice(address(mockPerp), 7000e18, 1e18);
    _bidOnAuction(1000e18, 1e18, 0, 0, false);
  }

  function testRevertsInDifferentCases() public {
    // Reverts when not enough cash transferred to cover margin/bid price
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) =
      _getBidActionData(10e18, 1e18, 0, 0, true, "");
    vm.expectRevert(IDutchAuction.DA_InsufficientCash.selector);
    _verifyAndMatch(actions, signatures, actionData);

    // Reverts when lastTradeId is invalid
    (actions, signatures, actionData) = _getBidActionData(1000e18, 1e18, 0, 420, true, "");
    vm.expectRevert(IDutchAuction.DA_InvalidLastTradeId.selector);
    _verifyAndMatch(actions, signatures, actionData);

    // Reverts when min bid price is not met
    (actions, signatures, actionData) = _getBidActionData(1000e18, 1e18, 1e18, 0, true, "");
    vm.expectRevert(IDutchAuction.DA_PriceLimitExceeded.selector);
    _verifyAndMatch(actions, signatures, actionData);

    // Still succeeds normally
    (actions, signatures, actionData) = _getBidActionData(1000e18, 1e18, 0, 0, true, "");
    _verifyAndMatch(actions, signatures, actionData);

    // Fails when trying to replay the same message
    vm.expectRevert(IBaseModule.BM_NonceAlreadyUsed.selector);
    _verifyAndMatch(actions, signatures, actionData);
  }

  function _bidOnAuction(uint cashTransfer, uint percent, int priceLimit, uint lastTradeId, bool merge) internal {
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) =
      _getBidActionData(cashTransfer, percent, priceLimit, lastTradeId, merge, "");
    _verifyAndMatch(actions, signatures, actionData);
  }

  function _getBidActionData(
    uint cashTransfer,
    uint percent,
    int priceLimit,
    uint lastTradeId,
    bool merge,
    bytes memory matchData
  ) internal view returns (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) {
    actions = new IActionVerifier.Action[](1);
    actionData = _encodeLiquidateData(liqAcc, cashTransfer, percent, priceLimit, lastTradeId, merge);

    signatures = new bytes[](1);

    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(liquidateModule), actionData, block.timestamp + 1 days, cam, cam, camPk);

    return (actions, signatures, matchData);
  }
}
