// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "v2-core/test/shared/mocks/MockERC20.sol";
import "v2-core/test/shared/mocks/MockManager.sol";

import "v2-core/src/assets/CashAsset.sol";
import "v2-core/src/Accounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_MatchingVerifyOrder is Test {
  using DecimalMath for uint;

  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts account;
  Matching matching;

  uint private immutable aliceKey;
  uint private immutable bobKey;
  address private immutable alice;
  address private immutable bob;
  bytes32 public domainSeparator;

  uint accountId;
  uint accountId2;
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
    matching = new Matching(account);

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");
    // 10000 USDC with 18 decimals
    usdc.mint(alice, 10000 ether);

    accountId = account.createAccount(alice, manager);
    accountId2 = account.createAccount(bob, manager);

    domainSeparator = matching.domainSeparator();
    matching.setWhitelist(address(this), true);

    vm.startPrank(alice);
    account.approve(address(matching), accountId);
    matching.openCLOBAccount(accountId);
    vm.stopPrank();
    vm.startPrank(bob);
    account.approve(address(matching), accountId2);
    matching.openCLOBAccount(accountId2);
    vm.stopPrank();
  }

  function testCannotTradeIfYouFrozen() public {
    vm.startPrank(alice);
    matching.freezeAccount(true);
    vm.stopPrank();
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(abi.encodeWithSelector(Matching.M_AccountFrozen.selector, alice));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeWithFrozenAccount() public {
    vm.startPrank(bob);
    matching.freezeAccount(true);
    vm.stopPrank();
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(abi.encodeWithSelector(Matching.M_AccountFrozen.selector, bob));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeIfExpired() public {
    uint expiry = block.timestamp + 1 days;
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, expiry, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, expiry, aliceKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you order has expired by a day
    vm.warp(block.timestamp + 2 days);
    vm.expectRevert(abi.encodeWithSelector(Matching.M_OrderExpired.selector, block.timestamp, expiry));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeZeroAmountInOrder() public {
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 0, 1e18, block.timestamp + 1 days, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeZeroAmountInMatch() public {
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, block.timestamp + 1 days, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, block.timestamp + 1 days, aliceKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 0, amount2: 0, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeToYourself() public {
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId, 1e18, 1e18, 1e18, block.timestamp + 1 days, aliceKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CannotTradeToSelf.selector, accountId));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeFillAmount() public {
    uint minPriceOrder1 = 1e18;
    uint fillAmount1 = 51 ether;
    uint fillAmount2 = 51 ether;
    uint assetAmount1 = 50 ether;
    uint assetAmount2 = 50 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) = _createSignedOrder(
      accountId, accountId2, minPriceOrder1, assetAmount1, fillAmount1, block.timestamp + 1 days, aliceKey
    );
    (Matching.LimitOrder memory order2, bytes memory signature2) = _createSignedOrder(
      accountId2, accountId, minPriceOrder1, assetAmount2, fillAmount2, block.timestamp + 1 days, bobKey
    );

    Matching.Match memory matchDetails =
      Matching.Match({amount1: fillAmount1, amount2: fillAmount2, signature1: signature1, signature2: signature2});

    // Revert since min price is 1.1 but fillAmounts are equal == 1
    vm.expectRevert(abi.encodeWithSelector(Matching.M_InsufficientFillAmount.selector, 1, assetAmount2, fillAmount1));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testOrdersInsideAgreedRange() public {
    uint minPriceOrder1 = 1e18;
    uint fillAmount1 = 50 ether;
    uint fillAmount2 = 9 ether;

    uint assetAmount1 = 100 ether;
    uint assetAmount2 = 100 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) = _createSignedOrder(
      accountId, accountId2, minPriceOrder1, assetAmount1, fillAmount1, block.timestamp + 1 days, aliceKey
    );
    (Matching.LimitOrder memory order2, bytes memory signature2) = _createSignedOrder(
      accountId2, accountId, minPriceOrder1, assetAmount2, fillAmount2, block.timestamp + 1 days, bobKey
    );

    Matching.Match memory matchDetails =
      Matching.Match({amount1: fillAmount1, amount2: fillAmount2, signature1: signature1, signature2: signature2});

    Matching.VerifiedOrder memory order = matching.submitTrade(matchDetails, order1, order2);
    assertEq(order.asset1Amount, fillAmount1);
  }

  function testOrdersOutsideAgreedRange() public {
    uint minPriceOrder1 = 1.1e18;
    uint fillAmount1 = 50 ether;
    uint fillAmount2 = 50 ether;
    uint assetAmount1 = 100 ether;
    uint assetAmount2 = 100 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) = _createSignedOrder(
      accountId, accountId2, minPriceOrder1, assetAmount1, fillAmount1, block.timestamp + 1 days, aliceKey
    );
    (Matching.LimitOrder memory order2, bytes memory signature2) = _createSignedOrder(
      accountId2, accountId, minPriceOrder1, assetAmount2, fillAmount2, block.timestamp + 1 days, bobKey
    );

    Matching.Match memory matchDetails =
      Matching.Match({amount1: fillAmount1, amount2: fillAmount2, signature1: signature1, signature2: signature2});

    // Revert since min price is 1.1 but fillAmounts are equal == 1
    vm.expectRevert(
      abi.encodeWithSelector(
        Matching.M_PriceBelowMinPrice.selector, minPriceOrder1, assetAmount1.divideDecimal(assetAmount2)
      )
    );
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeMismatchAssets() public {
    MockERC20 lyra = new MockERC20("LYRA", "LYRA");
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrderAsset(accountId, accountId2, address(usdc), address(lyra), 1, 1, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrderAsset(accountId2, accountId, address(usdc), address(usdc), 1, 1, bobKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(
      abi.encodeWithSelector(
        Matching.M_TradingDifferentAssets.selector, address(usdc), address(usdc), address(lyra), address(usdc)
      )
    );
    matching.submitTrade(matchDetails, order1, order2);
  }

  function testCannotTradeMismatchSubId() public {
    MockERC20 lyra = new MockERC20("LYRA", "LYRA");
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrderAsset(accountId, accountId2, address(usdc), address(lyra), 1, 1, aliceKey);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrderAsset(accountId2, accountId, address(lyra), address(usdc), 1, 2, bobKey);

    Matching.Match memory matchDetails =
      Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(abi.encodeWithSelector(Matching.M_TradingDifferentSubIds.selector, 1, 2, 1, 1));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function _createSignedOrder(
    uint fromAcc,
    uint toAcc,
    uint minPrice,
    uint assetAmount,
    uint fillAmount,
    uint expiry,
    uint pk
  ) internal view returns (Matching.LimitOrder memory order, bytes memory signature) {
    // Create LimitOrder
    order = Matching.LimitOrder({
      accountId1: fromAcc,
      accountId2: toAcc,
      asset1: IAsset(address(usdc)),
      subId1: 0,
      asset2: IAsset(address(usdc)),
      subId2: 0,
      asset1Amount: assetAmount,
      minPrice: minPrice,
      expirationTime: expiry,
      orderId: 1
    });

    // Sign the order
    bytes32 orderHash = matching.getOrderHash(order, fillAmount);
    signature = _sign(orderHash, pk);
  }

  function _createSignedOrderAsset(
    uint fromAcc,
    uint toAcc,
    address asset1,
    address asset2,
    uint subId1,
    uint subId2,
    uint pk
  ) internal view returns (Matching.LimitOrder memory order, bytes memory signature) {
    // Create LimitOrder
    order = Matching.LimitOrder({
      accountId1: fromAcc,
      accountId2: toAcc,
      asset1: IAsset(address(asset1)),
      subId1: subId1,
      asset2: IAsset(address(asset2)),
      subId2: subId2,
      asset1Amount: 1e18,
      minPrice: 1e18,
      expirationTime: block.timestamp + 1 days,
      orderId: 1
    });

    // Sign the order
    bytes32 orderHash = matching.getOrderHash(order, 1e18);
    signature = _sign(orderHash, pk);
  }

  function _sign(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
