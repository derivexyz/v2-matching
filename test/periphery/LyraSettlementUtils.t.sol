// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {SubAccountCreator} from "src/periphery/SubAccountCreator.sol";

import "../../src/periphery/LyraSettlementUtils.sol";

import "forge-std/console2.sol";

contract SubAccountCreatorTest is MatchingBase {
  LyraSettlementUtils public settler;
  uint64 expiry = 100000;

  function setUp() public override {
    super.setUp();

    settler = new LyraSettlementUtils();
  }

  function testCanSettleOptions() public {
    uint strike = 2000e18;

    feed.setSpot(1500e18, 1e18);

    usdc.mint(address(this), 1e36);
    usdc.approve(address(cash), 1e36);

    uint[] memory toSettle = new uint[](13);

    uint subA;
    uint subB;
    for (uint i = 0; i < 50; ++i) {
      // create two subaccounts and trade an option
      subA = subAccounts.createAccount(alice, IManager(address(pmrm)));
      subB = subAccounts.createAccount(bob, IManager(address(pmrm)));
      cash.deposit(subA, 200000e18);
      _transferOption(subA, subB, 10e18, expiry, strike, true);
      toSettle[i * 2 / 8] = toSettle[i * 2 / 8] | (subA << ((i * 2 % 8) * 32)) | (subB << ((i * 2 % 8 + 1) * 32));
    }

    int cashBefore = subAccounts.getBalance(subA, cash, 0);

    vm.warp(expiry + 1);
    uint subId = OptionEncoding.toSubId(expiry, strike, true);
    option.setMockedSubIdSettled(subId, true);
    option.setMockedTotalSettlementValue(subId, -500e18);

    settler.settleOptions(address(pmrm), address(option), toSettle);

    int cashAfter = subAccounts.getBalance(subA, cash, 0);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCanSettlePerps() public {
    uint strike = 2000e18;

    feed.setSpot(1500e18, 1e18);

    usdc.mint(address(this), 1e36);
    usdc.approve(address(cash), 1e36);

    uint[] memory toSettle = new uint[](13);

    uint subA;
    uint subB;
    for (uint i = 0; i < 50; ++i) {
      // create two subaccounts and trade an option
      subA = subAccounts.createAccount(alice, IManager(address(pmrm)));
      subB = subAccounts.createAccount(bob, IManager(address(pmrm)));
      cash.deposit(subA, 200000e18);
      cash.deposit(subB, 200000e18);
      _transferPerp(subA, subB, 10e18);
      toSettle[i * 2 / 8] = toSettle[i * 2 / 8] | (subA << ((i * 2 % 8) * 32)) | (subB << ((i * 2 % 8 + 1) * 32));

      mockPerp.mockAccountPnlAndFunding(subA, 100e18, 0);
      mockPerp.mockAccountPnlAndFunding(subB, -100e18, 0);
    }

    int cashBefore = subAccounts.getBalance(subA, cash, 0);

    settler.settlePerps(address(pmrm), toSettle);

    int cashAfter = subAccounts.getBalance(subA, cash, 0);
    // A trader loses 10 per perp
    assertEq(cashAfter - cashBefore, 100e18);
  }

  function _transferOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }

  function _transferPerp(uint fromAcc, uint toAcc, int amount) internal {
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: mockPerp,
      subId: 0,
      amount: amount,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }
}
