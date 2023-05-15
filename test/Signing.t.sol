// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "v2-core/test/shared/mocks/MockERC20.sol";
import "v2-core/test/shared/mocks/MockManager.sol";
import "v2-core/src/assets/CashAsset.sol";
import "v2-core/src/Accounts.sol";
import {Matching} from "src/Matching.sol";

/**
 * @dev Tests that users can sign for their orders
 */
contract UNIT_MatchingSigning is Test {
  IAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts account;
  Matching matching;

  uint private immutable privateKey;
  uint private immutable privateKey2;
  address private immutable pkOwner;
  address private immutable pkOwner2;
  bytes32 public domainSeparator;

  uint accountId;
  uint accountId2;
  uint positiveAmount = 1e18;
  uint negativeAmount = 2e18;

  constructor() {
    privateKey = 0xBEEF;
    privateKey2 = 0xBEEF2;
    pkOwner = vm.addr(privateKey);
    pkOwner2 = vm.addr(privateKey2);
  }

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    cashAsset = IAsset(address(usdc));
    matching = new Matching(account, cashAsset, 420);

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");
    // 10000 USDC with 18 decimals
    usdc.mint(pkOwner, 10000 ether);

    accountId = account.createAccount(pkOwner, manager);

    domainSeparator = matching.domainSeparator();
    matching.setWhitelist(address(this), true);

    vm.startPrank(pkOwner);
    account.approve(address(matching), accountId);
    matching.openCLOBAccount(accountId);
    vm.stopPrank();
  }

  function testValidSignature() public {
    // Create LimitOrder
    bytes32 tradingPair = matching.getTradingPair(IAsset(address(usdc)), IAsset(address(usdc)), 0, 0);
    Matching.LimitOrder memory order = Matching.LimitOrder({
      isBid: true,
      accountId1: accountId,
      accountId2: 0,
      amount: 100 ether,
      limitPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      maxFee: 0,
      salt: 0,
      tradingPair: tradingPair
    });

    // Sign the order
    bytes32 orderHash = matching.getOrderHash(order);
    bytes memory signature = _sign(orderHash, privateKey);

    // Verify the signature
    bool isValid = matching.verifySignature(accountId, orderHash, signature);
    assertEq(isValid, true);
  }

  function testInvalidSignature() public {
    // Create LimitOrder
    bytes32 tradingPair = matching.getTradingPair(IAsset(address(usdc)), IAsset(address(usdc)), 0, 0);
    Matching.LimitOrder memory order = Matching.LimitOrder({
      isBid: true,
      accountId1: accountId,
      accountId2: 0,
      amount: 100 ether,
      limitPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      maxFee: 0,
      salt: 0,
      tradingPair: tradingPair
    });

    // Sign the order with wrong pk for the accountId
    bytes32 orderHash = matching.getOrderHash(order);
    bytes memory signature = _sign(orderHash, privateKey2);

    // Verify the signature
    bool isValid = matching.verifySignature(accountId, orderHash, signature);
    assertEq(isValid, false);
  }

  function _sign(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  // just for coverage for now
  function testDomainSeparator() public view {
    matching.domainSeparator();
  }
}
