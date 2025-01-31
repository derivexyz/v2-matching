pragma solidity ^0.8.18;

import {IntegrationTestBase} from "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";
import "../../src/periphery/FeeSplitter.sol";

contract FeeSplitterTest is IntegrationTestBase {
  FeeSplitter public feeSplitter;
  IAsset public asset;
  uint public accountA;
  uint public accountB;

  function setUp() public {
    _setupIntegrationTestComplete();

    accountA = subAccounts.createAccount(address(this), srm);
    accountB = subAccounts.createAccount(address(this), markets["weth"].pmrm);

    feeSplitter = new FeeSplitter(subAccounts, srm, cash, 0.5e18, accountA, accountB);
    uint amount = 100e6;
    usdc.mint(address(this), amount);
    usdc.approve(address(cash), amount);
    cash.deposit(feeSplitter.subAcc(), amount);
  }

  function test_constructor() public {
    assertEq(address(feeSplitter.subAccounts()), address(subAccounts), "Incorrect subAccounts");
    assertEq(address(feeSplitter.cashAsset()), address(cash), "Incorrect cashAsset");
    assertFalse(feeSplitter.subAcc() == 0, "Incorrect subAcc");
    assertEq(feeSplitter.splitPercent(), 0.5e18, "Incorrect splitPercent");
    assertEq(feeSplitter.accountA(), accountA, "Incorrect accountA");
    assertEq(feeSplitter.accountB(), accountB, "Incorrect accountB");
  }

  function test_setSplit() public {
    feeSplitter.setSplit(0.6e18);
    assertEq(feeSplitter.splitPercent(), 0.6e18, "Incorrect splitPercent");

    vm.expectRevert(FeeSplitter.FS_InvalidSplitPercentage.selector);
    feeSplitter.setSplit(1.1e18);
  }

  function test_split() public {
    // before split
    assertEq(
      subAccounts.getBalance(feeSplitter.subAcc(), cash, 0), int(100e18), "Incorrect initial balance in FeeSplitter"
    );
    assertEq(subAccounts.getBalance(accountA, cash, 0), 0, "Account A should initially have 0 balance");
    assertEq(subAccounts.getBalance(accountB, cash, 0), 0, "Account B should initially have 0 balance");

    feeSplitter.split();

    // after split
    assertEq(
      subAccounts.getBalance(accountA, cash, 0), int(50e18), "Account A should have half of the funds after split"
    );
    assertEq(
      subAccounts.getBalance(accountB, cash, 0), int(50e18), "Account B should have half of the funds after split"
    );

    vm.expectRevert(FeeSplitter.FS_NoBalanceToSplit.selector);
    feeSplitter.split();
  }

  function test_recover() public {
    uint oldSubAcc = feeSplitter.subAcc();
    feeSplitter.recoverSubAccount(address(this));
    uint newSubAcc = feeSplitter.subAcc();
    assertEq(
      subAccounts.ownerOf(newSubAcc), address(feeSplitter), "New subAcc should be owned by fee splitter contract"
    );
    assertEq(subAccounts.ownerOf(oldSubAcc), address(this), "Old subAcc should be owned by this contract");
    assertFalse(oldSubAcc == newSubAcc);
  }

  function test_split100percent() public {
    feeSplitter.setSplit(1e18);
    feeSplitter.split();
    assertEq(
      subAccounts.getBalance(accountA, cash, 0), int(100e18), "Account A should have all of the funds after split"
    );
    assertEq(subAccounts.getBalance(accountB, cash, 0), 0, "Account B should have 0 balance after split");
  }

  function test_split0percent() public {
    feeSplitter.setSplit(0);
    feeSplitter.split();
    assertEq(subAccounts.getBalance(accountA, cash, 0), 0, "Account A should have 0 balance after split");
    assertEq(
      subAccounts.getBalance(accountB, cash, 0), int(100e18), "Account B should have all of the funds after split"
    );
  }

  function test_setSubAccounts() public {
    feeSplitter.setSubAccounts(accountB, accountA);
    assertEq(feeSplitter.accountA(), accountB, "Incorrect accountA");
    assertEq(feeSplitter.accountB(), accountA, "Incorrect accountB");

    vm.expectRevert(FeeSplitter.FS_InvalidSubAccount.selector);
    feeSplitter.setSubAccounts(0, accountA);

    vm.expectRevert(FeeSplitter.FS_InvalidSubAccount.selector);
    feeSplitter.setSubAccounts(accountB, 0);
  }
}
