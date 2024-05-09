// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ITradeModule} from "../../src/interfaces/ITradeModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";
import "../../src/periphery/LyraAuctionUtils.sol";
import "../shared/MatchingBase.t.sol";
import {IntegrationTestBase} from "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";
import {LRTCCTSA} from "../../src/tokenizedSubaccounts/LRTCCTSA.sol";
import {BaseTSA} from "../../src/tokenizedSubaccounts/BaseTSA.sol";
import "../../src/tokenizedSubaccounts/TSAPreDeposit.sol";
import "v2-core/test/shared/mocks/MockERC20.sol";



contract TSAPreDepositTest is Test {
  MockERC20 internal erc20;
  TSAPreDeposit internal preDeposit;

  address internal alice = address(0x123);

  function setUp() public {
    erc20 = new MockERC20("token", "token");
    preDeposit = new TSAPreDeposit(erc20);
  }

  function testCanDepositWithdrawAndMigrate() public {
    erc20.mint(alice, 1500e18);

    vm.prank(alice);
    erc20.approve(address(preDeposit), 1500e18);

    // Cannot deposit until cap is set
    vm.prank(alice);
    vm.expectRevert("Deposit exceeds cap");
    preDeposit.deposit(1000e18);

    preDeposit.setDepositCap(500e18);

    // Cannot deposit more than cap
    vm.prank(alice);
    vm.expectRevert("Deposit exceeds cap");
    preDeposit.deposit(1000e18);

    // Can deposit exactly the whole cap
    vm.prank(alice);
    preDeposit.deposit(200e18);
    vm.prank(alice);
    preDeposit.deposit(300e18);

    assertEq(preDeposit.deposits(alice), 500e18);

    // Cannot deposit more than when used by others
    vm.prank(alice);
    vm.expectRevert("Deposit exceeds cap");
    preDeposit.deposit(100e18);

    // Can increase cap to deposit more
    preDeposit.setDepositCap(1000e18);

    vm.prank(alice);
    preDeposit.deposit(500e18);

    assertEq(preDeposit.deposits(alice), 1000e18);

    // At this point Alice is still holding 500, and has deposited 1000

    // Cannot withdraw more than deposited
    vm.prank(alice);
    vm.expectRevert("Insufficient balance");
    preDeposit.withdraw(1001e18);

    // Can withdraw some
    vm.prank(alice);
    preDeposit.withdraw(400e18);
    assertEq(preDeposit.deposits(alice), 600e18);
    assertEq(erc20.balanceOf(address(preDeposit)), 600e18);
    assertEq(erc20.balanceOf(alice), 900e18);

    // Alice cant force migrate
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    preDeposit.migrate();

    // Owner can migrate
    preDeposit.migrate();
    assertEq(erc20.balanceOf(address(preDeposit)), 0);
    assertEq(erc20.balanceOf(alice), 900e18);
    // this is owner, so gets all the remaining funds when migrated
    assertEq(erc20.balanceOf(address(this)), 600e18);
  }
}
