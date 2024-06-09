pragma solidity ^0.8.18;

import "../TSATestUtils.sol";

/*
Tests for upgrading from the predeposit contract
- ✅existing balances are migrated successfully
- migrated balances can be deposited to the subaccount
- accountValue is accurate when upgraded
- fees start accruing only after upgrade
- upgrading can update name
- upgrading cannot update owner
*/
contract LRTCCTSA_UpgradeTest is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
  }

  function testExistingBalancesMigrated() public {
    deployPredeposit(address(usdc));

    TokenizedSubAccount preTsa = TokenizedSubAccount(address(proxy));

    // deposit some funds
    usdc.mint(address(this), 1_000_000e6);
    usdc.approve(address(preTsa), 1_000_000e6);
    preTsa.depositFor(address(this), 1_000_000e6);

    // Check balances
    assertEq(preTsa.balanceOf(address(this)), 1_000_000e6);
    assertEq(usdc.balanceOf(address(preTsa)), 1_000_000e6);
    assertEq(usdc.balanceOf(address(this)), 0);

    // withdraw 1000
    preTsa.withdrawTo(address(this), 1000e6);

    // Check balances
    assertEq(preTsa.balanceOf(address(this)), 999_000e6);
    assertEq(usdc.balanceOf(address(preTsa)), 999_000e6);
    assertEq(usdc.balanceOf(address(this)), 1_000e6);

    // Upgrade
    upgradeToLRTCCTSA("usdc");
    LRTCCTSA ccTSA = LRTCCTSA(address(proxy));
    setupLRTCCTSA();
    ccTSA.setShareKeeper(address(this), true);

    // Check balances
    assertEq(tsa.balanceOf(address(this)), 999_000e6);
    assertEq(usdc.balanceOf(address(tsa)), 999_000e6);

    // Cannot call TSA functions
    vm.expectRevert();
    preTsa.depositFor(address(this), 1_000e6);

    vm.expectRevert();
    preTsa.withdrawTo(address(this), 1_000e6);

    // Withdraw a portion
    assertEq(ccTSA.getAccountValue(false), 999_000e6);

    ccTSA.requestWithdrawal(500e6);
    ccTSA.processWithdrawalRequests(1);

    // Check balances
    assertEq(ccTSA.balanceOf(address(this)), 998_500e6);
    assertEq(usdc.balanceOf(address(ccTSA)), 998_500e6);
    assertEq(usdc.balanceOf(address(this)), 1_500e6);
  }
}
