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

  function setUp() public override {
    super.setUp();
    feeSplitter = new FeeSplitter(subAccounts, srm);
    feeSplitter.setSubAccounts(accountA, accountB);
    feeSplitter.setSplit(50);
    uint amount = 100e18;
    cashAsset.mint(address(this), amount);
    cashAsset.approve(address(subAccounts), amount);
    cashAsset.deposit(feeSplitter.subAcc(), amount);
  }

  function test_split() public {
    // before split
    assertEq(subAccounts.getBalance(feeSplitter.subAcc(), cashAsset, 0), int(100e18), "Incorrect initial balance in FeeSplitter");
    assertEq(subAccounts.getBalance(accountA, cashAsset, 0), 0, "Account A should initially have 0 balance");
    assertEq(subAccounts.getBalance(accountB, cashAsset, 0), 0, "Account B should initially have 0 balance");

    feeSplitter.split();

    // after split
    assertEq(subAccounts.getBalance(accountA, cashAsset, 0), int(50e18), "Account A should have half of the funds after split");
    assertEq(subAccounts.getBalance(accountB, cashAsset, 0), int(50e18), "Account B should have half of the funds after split");
  }
}
