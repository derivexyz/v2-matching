// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FXToken} from "../../src/fx/FXToken.sol";

contract FXTokenTest is Test {
  FXToken token;

  address admin = address(0x1);
  address minter = address(0x2);
  address blocker = address(0x2);
  address alice = address(0xa);
  address bob = address(0xb);
  address charlie = address(0xc);

  function setUp() public {
    // admin deploys, so becomes admin
    vm.startPrank(admin);
    FXToken fxTokenImplementation = new FXToken();

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(fxTokenImplementation),
      address(alice),
      abi.encodeWithSelector(fxTokenImplementation.initialize.selector, "fx USDC", "fxUSDC", 6)
    );
    token = FXToken(address(proxy));

    // Set roles
    token.grantRole(token.MINTER_ROLE(), minter);
    token.grantRole(token.BLOCK_MANAGER_ROLE(), blocker);

    vm.stopPrank();
  }

  function testInitialSetup() public view {
    assertEq(token.name(), "fx USDC");
    assertEq(token.symbol(), "fxUSDC");
    assertEq(token.decimals(), 6);
    assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
    assertTrue(token.hasRole(token.BLOCK_MANAGER_ROLE(), blocker));
  }

  function testMint() public {
    vm.prank(minter);
    token.mint(alice, 100);

    assertEq(token.balanceOf(alice), 100);
  }

  function testBurn() public {
    vm.prank(minter);
    token.mint(alice, 100);

    assertEq(token.balanceOf(alice), 100);

    vm.prank(minter);
    token.burn(alice, 50);

    assertEq(token.balanceOf(alice), 50);
  }

  function testBlockUser() public {
    vm.prank(minter);
    token.mint(bob, 100);

    vm.prank(blocker);
    token.setBlocked(bob, true);

    assertTrue(token.isBlocked(bob));

    // Minting to a blocked user should revert
    vm.prank(minter);
    vm.expectRevert("FxToken: recipient is blocked");
    token.mint(bob, 100);

    // Burning from a blocked user is allowed
    vm.prank(minter);
    token.burn(bob, 50);

    assertEq(token.balanceOf(bob), 50);

    vm.prank(minter);
    token.mint(alice, 100);

    assertEq(token.balanceOf(alice), 100);

    vm.prank(alice);
    vm.expectRevert("FxToken: recipient is blocked");
    token.transfer(bob, 50);

    // A blocked user cannot transfer tokens
    vm.prank(bob);
    vm.expectRevert("FxToken: sender is blocked");
    token.transfer(alice, 50);

    // A blocked user approving is allowed, but the spender cannot transfer
    vm.prank(bob);
    token.approve(alice, 50);

    vm.prank(alice);
    vm.expectRevert("FxToken: sender is blocked");
    token.transferFrom(bob, alice, 50);

    // Cannot transferFrom to a blocked user
    vm.prank(alice);
    token.approve(charlie, 50);

    vm.prank(charlie);
    vm.expectRevert("FxToken: recipient is blocked");
    token.transferFrom(alice, bob, 50);

    // Cannot spend allowance if spender is blocked
    vm.prank(alice);
    token.approve(bob, 50);

    vm.prank(bob);
    vm.expectRevert("FxToken: spender is blocked");
    token.transferFrom(alice, charlie, 50);
  }

  function testCannotBlockZeroAddress() public {
    vm.prank(blocker);
    vm.expectRevert("FxToken: cannot block zero address");
    token.setBlocked(address(0), true);
  }



}