// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "v2-core/test/shared/mocks/MockManager.sol";
import "v2-core/test/shared/mocks/MockFeed.sol";
import "v2-core/test/integration-tests/shared/IntegrationTestBase.sol";
import {Matching} from "src/Matching.sol";

/**
 * @dev Unit tests for the whitelisted functions
 */
contract UNIT_MatchingAccountManagement is Test {
  using SafeCast for int;

  address cash;
  MockERC20 usdc;
  MockManager manager;
  MockFeed feed;
  Accounts account;
  Matching matching;
  Option option;

  uint private immutable aliceKey;
  uint private immutable bobKey;
  address private immutable alice;
  address private immutable bob;
  uint public constant DEFAULT_DEPOSIT = 5000e18;
  bytes32 public domainSeparator;

  uint public COOLDOWN_SEC = 1 hours;

  uint aliceAcc;
  uint bobAcc;
  uint callId;
  uint positiveAmount = 1e18;
  uint negativeAmount = 2e18;

  constructor() {
    aliceKey = 0xBEEF;
    bobKey = 0xBEEF2;
    alice = vm.addr(aliceKey);
    bob = vm.addr(bobKey);
  }

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    cash = address(usdc);
    matching = new Matching(account, cash, 420, COOLDOWN_SEC);

    manager = new MockManager(address(account));
    feed = new MockFeed();
    usdc = new MockERC20("USDC", "USDC");
    // 10000 USDC with 18 decimals
    
    usdc.mint(alice, 10000 ether);
    aliceAcc = account.createAccount(alice, manager);
    bobAcc = account.createAccount(bob, manager);
    
    domainSeparator = matching.domainSeparator();
    matching.setWhitelist(address(this), true);

    option = new Option(account, address(feed));
  option.setWhitelistManager(address(manager), true);
   

    callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
    transferBatch[0] = IAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: 10e18,
      assetData: bytes32(0)
    });
    account.submitTransfers(transferBatch, "");

     vm.startPrank(alice);
    account.approve(address(matching), aliceAcc);
    matching.openCLOBAccount(aliceAcc);
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(address(matching), bobAcc);
    matching.openCLOBAccount(bobAcc);
    vm.stopPrank();
  }

  function testCanWithdrawAccount() public {
    vm.startPrank(alice);
    matching.requestWithdraw(aliceAcc);

    assertEq(account.ownerOf(aliceAcc), address(matching));

    // Should revert since cooldown has no elapsed
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CooldownNotElapsed.selector, COOLDOWN_SEC));
    matching.closeCLOBAccount(aliceAcc);

    vm.warp(block.timestamp + COOLDOWN_SEC);
    matching.closeCLOBAccount(aliceAcc);
    assertEq(account.ownerOf(aliceAcc), address(alice));
  }

  function testCannotRequestWithdraw() public {
    vm.startPrank(bob);

    // Should revert since bob is not owner
    vm.expectRevert(abi.encodeWithSelector(Matching.M_NotOwnerAddress.selector, address(bob), address(alice)));
    matching.requestWithdraw(aliceAcc);
  }

  function testCanTransferAsset() public {
    uint transferAmount = 10e18;
    // int alicePrevious = getCashBalance(aliceAcc);
    // int bobPrevious = getCashBalance(bobAcc);
    // assertEq(alicePrevious.toUint256(), DEFAULT_DEPOSIT);
    // assertEq(bobPrevious.toUint256(), DEFAULT_DEPOSIT);

    int bal = account.getBalance(aliceAcc, option, callId);
    console2.log("CallId:", bal);

    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({asset: IAsset(cash), subId: 0, amount: transferAmount, fromAcc: aliceAcc, toAcc: aliceAcc});

    // Sign the transfer
    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, aliceKey);

    matching.transferAsset(transfer, signature);
    int aliceAfter = getCashBalance(aliceAcc);
    int bobAfter = getCashBalance(bobAcc);
    assertEq(aliceAfter.toUint256(), DEFAULT_DEPOSIT - transferAmount);
    assertEq(bobAfter.toUint256(), DEFAULT_DEPOSIT + transferAmount);
  }

  // function testCannotTransferAsset() public {
  //   // Remove whitelist and try to transfer
  //   matching.setWhitelist(address(this), false);

  //   vm.expectRevert(Matching.M_NotWhitelisted.selector);
  //   matching.transferAsset(aliceAcc, bobAcc, cash, 0, 1e18);
  // }

  function _sign(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  /**
   * @dev view function to help writing integration test
   */
  function getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, IAsset(cash), 0);
  }

  /**
   * @dev helper to mint USDC and deposit cash for account (from user)
   */
  function _depositCash(address user, uint acc, uint amountCash) internal {
    uint amountUSDC = amountCash / 1e12;
    usdc.mint(user, amountUSDC);

    vm.startPrank(user);
    usdc.approve(cash, type(uint).max);
    ICashAsset(cash).deposit(acc, amountUSDC);
    vm.stopPrank();
  }
}
