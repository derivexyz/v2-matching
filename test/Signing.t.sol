// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "v2-core/../test/shared/mocks/MockERC20.sol";
import "v2-core/../test/shared/mocks/MockManager.sol";

import "v2-core/assets/CashAsset.sol";
import "v2-core/Accounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_MatchingSigning is Test {
  CashAsset cashAsset;
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
    matching = new Matching(account);

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");
    // 10000 USDC with 18 decimals
    usdc.mint(pkOwner, 10000 ether);

    accountId = account.createAccount(pkOwner, manager);

    domainSeparator = matching.domainSeparator();

    vm.startPrank(pkOwner);
    account.approve(address(matching), accountId);
    matching.openCLOBAccount(accountId);
    vm.stopPrank();
  }

  function testValidSignature() public {
    // Create LimitOrder
    Matching.LimitOrder memory order = Matching.LimitOrder({
      accountId1: accountId,
      accountId2: 0,
      asset1: IAsset(address(usdc)),
      subId1: 0,
      asset2: IAsset(address(usdc)),
      subId2: 0,
      asset1Amount: 100 ether,
      minPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      orderId: 1
    });

    // Sign the order
    uint fillAmount = 50 ether;
    bytes32 orderHash = matching.getOrderHash(order, fillAmount);

    bytes memory signature = _sign(orderHash, privateKey);

    // Verify the signature
    bool isValid = matching.verifySignature(order, fillAmount, signature);
    assertEq(isValid, true);
  }

  function testInvalidSignature() public {
    // Create LimitOrder
    Matching.LimitOrder memory order = Matching.LimitOrder({
      accountId1: accountId,
      accountId2: 0,
      asset1: IAsset(address(usdc)),
      subId1: 0,
      asset2: IAsset(address(usdc)),
      subId2: 0,
      asset1Amount: 100 ether,
      minPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      orderId: 1
    });

    // Sign the order with the wrong pk
    uint fillAmount = 50 ether;
    bytes32 orderHash = matching.getOrderHash(order, fillAmount);
    bytes memory signature = _sign(orderHash, privateKey2);

    // Verify the signature
    bool isValid = matching.verifySignature(order, fillAmount, signature);
    assertEq(isValid, false);
  }

  function testInvalidFillAmountSignature() public {
    // Create LimitOrder
    Matching.LimitOrder memory order = Matching.LimitOrder({
      accountId1: accountId,
      accountId2: 0,
      asset1: IAsset(address(usdc)),
      subId1: 0,
      asset2: IAsset(address(usdc)),
      subId2: 0,
      asset1Amount: 100 ether,
      minPrice: 1 ether,
      expirationTime: block.timestamp + 1 days,
      orderId: 1
    });

    // Sign the order with correct pk but incorrect fillAmount
    uint fillAmount = 50 ether;
    bytes32 orderHash = matching.getOrderHash(order, fillAmount + 1 ether);
    bytes memory signature = _sign(orderHash, privateKey);

    // Verify the signature
    bool isValid = matching.verifySignature(order, fillAmount, signature);
    assertEq(isValid, false);
  }

  function _sign(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  // just for coverage for now
  function testDomainSeparator() public view {
    account.domainSeparator();
  }
}
