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
    matching = new Matching(account, cash, 420);
    matching.setWithdrawAccountCooldown(COOLDOWN_SEC);
    matching.setWithdrawCashCooldown(COOLDOWN_SEC);
    matching.setSessionKeyCooldown(COOLDOWN_SEC);

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

    vm.startPrank(bob);
    callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);
    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
    transferBatch[0] = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: option,
      subId: callId,
      amount: 1e18,
      assetData: bytes32(0)
    });

    account.submitTransfers(transferBatch, "");
    vm.stopPrank();

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
    matching.requestCloseCLOBAccount(aliceAcc);

    assertEq(account.ownerOf(aliceAcc), address(matching));

    // Should revert since cooldown has no elapsed
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CooldownNotElapsed.selector, COOLDOWN_SEC));
    matching.completeCloseCLOBAccount(aliceAcc);

    vm.warp(block.timestamp + COOLDOWN_SEC);
    matching.completeCloseCLOBAccount(aliceAcc);
    assertEq(account.ownerOf(aliceAcc), address(alice));
  }

  function testCannotRequestWithdraw() public {
    vm.startPrank(bob);

    // Should revert since bob is not owner
    vm.expectRevert(abi.encodeWithSelector(Matching.M_NotOwnerAddress.selector, address(bob), address(alice)));
    matching.requestCloseCLOBAccount(aliceAcc);
  }

  function testCanTransferAsset() public {
    vm.startPrank(bob);
    matching.registerSessionKey(bob, alice, block.timestamp + 1 days);
    vm.stopPrank();

    int aliceBefore = account.getBalance(aliceAcc, option, callId);
    int bobBefore = account.getBalance(bobAcc, option, callId);
    assertEq(aliceBefore, 1e18);
    assertEq(bobBefore, -1e18);

    bytes32 assetHash = matching.getAssetHash(option, callId);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: bobAcc, assetHash: assetHash});

    // Sign the transfer
    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, aliceKey);

    Matching.TransferAsset[] memory transfers = new Matching.TransferAsset[](1);
    transfers[0] = transfer;
    bytes[] memory signatures = new bytes[](1);
    signatures[0] = signature;
    IAsset[] memory assets = new IAsset[](1);
    assets[0] = option;
    uint[] memory subIds = new uint[](1);
    subIds[0] = callId;

    matching.submitTransfers(transfers, assets, subIds, signatures);

    int aliceAfter = account.getBalance(aliceAcc, option, callId);
    int bobAfter = account.getBalance(bobAcc, option, callId);
    assertEq(aliceAfter, 0);
    assertEq(bobAfter, 0);
  }

  // Mint new account with owner as alice but session key from bob
  function testMintAccountAndTransferSignature() public {
    // First register bob session key to alice address
    vm.startPrank(alice);
    matching.registerSessionKey(alice, bob, block.timestamp + 1 days);
    vm.stopPrank();

    Matching.MintAccount memory newAccount = Matching.MintAccount({owner: alice, manager: address(manager)});

    // Create transfer request
    bytes32 assetHash = matching.getAssetHash(IAsset(option), callId);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: bobAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, bobKey);

    // New account is minted
    uint newId = matching.mintAccountAndTransfer(newAccount, transfer, IAsset(option), callId, signature);
    assertEq(newId, 3);
  }

  // User must wait for cooldown to complete
  function testCannotDeregisterSessionKey() public {
    vm.startPrank(alice);
    matching.registerSessionKey(alice, bob, block.timestamp + 1 days);
    matching.requestDeregisterSessionKey(bob);

    assertEq(matching.permissions(bob, alice), block.timestamp + 1 days);

    vm.expectRevert(abi.encodeWithSelector(Matching.M_CooldownNotElapsed.selector, COOLDOWN_SEC));
    matching.completeDeregisterSessionKey(bob);
  }

  // User waits for cooldown to deregister
  function testDeregisterSessionKey() public {
    vm.startPrank(alice);
    matching.registerSessionKey(alice, bob, block.timestamp + 1 days);
    matching.requestDeregisterSessionKey(bob);
    assertEq(matching.permissions(bob, alice), block.timestamp + 1 days);

    assertEq(matching.sessionKeyCooldown(bob), block.timestamp);
    vm.warp(block.timestamp + COOLDOWN_SEC);
    matching.completeDeregisterSessionKey(bob);

    assertEq(matching.permissions(bob, alice), 0);
  }

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
