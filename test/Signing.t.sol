// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "v2-core/test/shared/mocks/MockERC20.sol";
import "v2-core/test/shared/mocks/MockManager.sol";
import "v2-core/src/assets/CashAsset.sol";
import "v2-core/src/SubAccounts.sol";
import {Matching} from "src/Matching.sol";

/**
 * @dev Tests that users can sign for their orders
 */
contract UNIT_MatchingSigning is Test {
  address cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts account;
  Matching matching;

  uint private immutable aliceKey;
  uint private immutable bobKey;
  address private immutable alice;
  address private immutable bob;
  bytes32 public domainSeparator;

  uint aliceAcc;
  uint bobAcc;
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
    cashAsset = address(usdc);
    matching = new Matching(account, cashAsset, 420);

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");
    // 10000 USDC with 18 decimals
    usdc.mint(alice, 10000 ether);

    aliceAcc = account.createAccount(alice, manager);

    domainSeparator = matching.domainSeparator();
    matching.setWhitelist(address(this), true);

    vm.startPrank(alice);
    account.approve(address(matching), aliceAcc);
    matching.openCLOBAccount(aliceAcc);
    vm.stopPrank();
  }

  function testValidSignature() public {
    // Create LimitOrder
    bytes32 instrumentHash = matching.getInstrument(IAsset(address(usdc)), IAsset(address(usdc)), 0, 0);
    Matching.LimitOrder memory order = Matching.LimitOrder({
      isBid: true,
      accountId1: aliceAcc,
      amount: 100 ether,
      limitPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      maxFee: 0,
      nonce: 0,
      instrumentHash: instrumentHash
    });

    // Sign the order
    bytes32 orderHash = matching.getOrderHash(order);
    bytes memory signature = _sign(orderHash, aliceKey);

    // Verify the signature
    bool isValid = matching.verifySignature(aliceAcc, orderHash, signature);
    assertEq(isValid, true);
  }

  function testInvalidSignature() public {
    // Create LimitOrder
    bytes32 instrumentHash = matching.getInstrument(IAsset(address(usdc)), IAsset(address(usdc)), 0, 0);
    Matching.LimitOrder memory order = Matching.LimitOrder({
      isBid: true,
      accountId1: aliceAcc,
      amount: 100 ether,
      limitPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      maxFee: 0,
      nonce: 0,
      instrumentHash: instrumentHash
    });

    // Sign the order with wrong pk for the aliceAcc
    bytes32 orderHash = matching.getOrderHash(order);
    bytes memory signature = _sign(orderHash, bobKey);

    // Verify the signature
    bool isValid = matching.verifySignature(aliceAcc, orderHash, signature);
    assertEq(isValid, false);
  }

  function _sign(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  function testTransferSignatureAsOwner() public {
    // Create transfer request
    bytes32 assetHash = matching.getAssetHash(IAsset(cashAsset), 0);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, aliceKey);

    // Verify the signature
    bool isValid = matching.verifySignature(aliceAcc, transferHash, signature);
    assertEq(isValid, true);
  }

  function testCannotTransferSignatureAsSessionKey() public {
    // Don't register session key first
    bytes32 assetHash = matching.getAssetHash(IAsset(cashAsset), 0);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, bobKey);

    // Verify the signature is false
    bool isValid = matching.verifySignature(aliceAcc, transferHash, signature);
    assertEq(isValid, false);
  }

  function testTransferSignatureAsSessionKey() public {
    // Register session key first
    vm.startPrank(alice);
    matching.registerSessionKey(bob, block.timestamp + 1 days);
    vm.stopPrank();

    // Create transfer request
    bytes32 assetHash = matching.getAssetHash(IAsset(cashAsset), 0);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, bobKey);

    // Verify the signature
    bool isValid = matching.verifySignature(aliceAcc, transferHash, signature);
    assertEq(isValid, true);
  }

  function testSessionKeyExpiry() public {
    // Register session key first
    vm.startPrank(alice);
    matching.registerSessionKey(bob, block.timestamp + 1 days);
    vm.stopPrank();

    // Create transfer request
    bytes32 assetHash = matching.getAssetHash(IAsset(cashAsset), 0);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, bobKey);

    // Verify the signature
    bool isValid = matching.verifySignature(aliceAcc, transferHash, signature);
    assertEq(isValid, true);

    // Fast forward past expiry and check the signature is false
    vm.warp(block.timestamp + 2 days);
    isValid = matching.verifySignature(aliceAcc, transferHash, signature);
    assertEq(isValid, false);
  }

  // Sign for a different amount of transfer
  function testSessionKeyDifferentTransfer() public {
    // Register session key first
    vm.startPrank(alice);
    matching.registerSessionKey(bob, block.timestamp + 1 days);
    vm.stopPrank();

    // Create transfer request
    bytes32 assetHash = matching.getAssetHash(IAsset(cashAsset), 0);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, bobKey);

    // Verify the signature
    bool isValid = matching.verifySignature(aliceAcc, transferHash, signature);
    assertEq(isValid, true);

    Matching.TransferAsset memory transfer2 =
      Matching.TransferAsset({amount: 2e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash2 = matching.getTransferHash(transfer2);
    bytes memory signature2 = _sign(transferHash2, bobKey);

    // Using the signature for the transfer of `2e18` not `1e18`
    isValid = matching.verifySignature(aliceAcc, transferHash, signature2);
    assertEq(isValid, false);
  }

  // Try mint new account with owner as alice but session key from bob
  function testCannotMintAccountSignature() public {
    Matching.MintAccount memory newAccount = Matching.MintAccount({owner: alice, manager: address(manager)});

    // Create transfer request
    bytes32 assetHash = matching.getAssetHash(IAsset(cashAsset), 0);
    Matching.TransferAsset memory transfer =
      Matching.TransferAsset({amount: 1e18, fromAcc: aliceAcc, toAcc: aliceAcc, assetHash: assetHash});

    bytes32 transferHash = matching.getTransferHash(transfer);
    bytes memory signature = _sign(transferHash, bobKey);

    // New account is minted
    vm.expectRevert(abi.encodeWithSelector(Matching.M_SessionKeyInvalid.selector, bob));
    matching.mintAccountAndTransfer(newAccount, transfer, IAsset(cashAsset), 0, signature);
  }

  // just for coverage for now
  function testDomainSeparator() public view {
    matching.domainSeparator();
  }
}
