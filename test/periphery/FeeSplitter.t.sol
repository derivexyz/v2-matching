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

    feeSplitter = new FeeSplitter(subAccounts, srm, cash);
    feeSplitter.setSubAccounts(accountA, accountB);
    feeSplitter.setSplit(0.5e18);
    uint amount = 100e6;
    usdc.mint(address(this), amount);
    usdc.approve(address(cash), amount);
    cash.deposit(feeSplitter.subAcc(), amount);
  }

  function test_split() public {
    // before split
    assertEq(subAccounts.getBalance(feeSplitter.subAcc(), cash, 0), int(100e18), "Incorrect initial balance in FeeSplitter");
    assertEq(subAccounts.getBalance(accountA, cash, 0), 0, "Account A should initially have 0 balance");
    assertEq(subAccounts.getBalance(accountB, cash, 0), 0, "Account B should initially have 0 balance");

    feeSplitter.split();

    // after split
    assertEq(subAccounts.getBalance(accountA, cash, 0), int(50e18), "Account A should have half of the funds after split");
    assertEq(subAccounts.getBalance(accountB, cash, 0), int(50e18), "Account B should have half of the funds after split");
  }
}
