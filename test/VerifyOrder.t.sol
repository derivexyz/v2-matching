// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "v2-core/test/shared/mocks/MockERC20.sol";
import "v2-core/test/shared/mocks/MockManager.sol";
import "v2-core/src/assets/CashAsset.sol";
import "v2-core/src/Accounts.sol";
import {Matching} from "src/Matching.sol";

/**
 * @dev Unit tests for verifying an order
 */
contract UNIT_MatchingVerifyOrder is Test {
  using DecimalMath for uint;

  IAsset cashAsset;
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

  constructor() {
    aliceKey = 0xBEEF;
    bobKey = 0xBEEF2;
    alice = vm.addr(aliceKey);
    bob = vm.addr(bobKey);
  }

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    cashAsset = IAsset(address(usdc));
    matching = new Matching(account, cashAsset, 420);

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

  // Attempt to trade with your frozen account
  function testCannotTradeIfYouFrozen() public {
    vm.startPrank(alice);
    matching.freezeAccount(true);
    vm.stopPrank();

    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, accountId, 1e18, 1e18, 0, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 1e18,
      amount2: 1e18,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(abi.encodeWithSelector(Matching.M_AccountFrozen.selector, alice));
    matching.submitTrade(matchDetails, limitOrder1, limitOrder2);
  }

  // Attempt to trade with another account that is frozen
  function testCannotTradeWithFrozenAccount() public {
    vm.startPrank(bob);
    matching.freezeAccount(true);
    vm.stopPrank();
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, accountId, 1e18, 1e18, 0, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 1e18,
      amount2: 1e18,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(abi.encodeWithSelector(Matching.M_AccountFrozen.selector, bob));
    matching.submitTrade(matchDetails, limitOrder1, limitOrder2);
  }

  // Attempt to trade an order that has expired
  function testCannotTradeIfExpired() public {
    uint expiry = block.timestamp + 1 days;
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, 0, expiry, aliceKey, true);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, 0, expiry, aliceKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 1e18,
      amount2: 1e18,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you order has expired by a day
    vm.warp(block.timestamp + 2 days);
    vm.expectRevert(abi.encodeWithSelector(Matching.M_OrderExpired.selector, block.timestamp, expiry));
    matching.submitTrade(matchDetails, order1, order2);
  }

  // Attempt to trade 0 amount in order
  function testCannotTradeZeroAmountInOrder() public {
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 0, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, accountId, 1e18, 1e18, 0, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 1e18,
      amount2: 1e18,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
    matching.submitTrade(matchDetails, limitOrder1, limitOrder2);
  }

  // Attemp to trade 0 fill amount
  function testCannotTradeZeroAmountInMatch() public {
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, 1e18, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, accountId, 1e18, 1e18, 0, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 0,
      amount2: 0,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
    matching.submitTrade(matchDetails, limitOrder1, limitOrder2);
  }

  // Attempt to trade with yourself
  function testCannotTradeToYourself() public {
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId, 1e18, 1e18, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId, accountId, 1e18, 1e18, 0, 0, block.timestamp + 1 days, aliceKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 1e18,
      amount2: 1e18,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CannotTradeToSelf.selector, accountId));
    matching.submitTrade(matchDetails, limitOrder1, limitOrder2);
  }

  // Attempt to fill amount more than the order
  function testCannotTradeFillAmount() public {
    uint limitPriceOrder1 = 1e18;
    uint fillAmount = 51 ether;
    uint assetAmount = 50 ether;

    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 1e18, assetAmount, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, accountId, 1e18, assetAmount, 0, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: fillAmount,
      amount2: fillAmount,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since min price is 1.1 but fillAmounts are equal == 1
    vm.expectRevert(abi.encodeWithSelector(Matching.M_InsufficientFillAmount.selector, 1, assetAmount, fillAmount));
    matching.submitTrade(matchDetails, limitOrder1, limitOrder2);
  }

  // Attempt to trade within limit price for both sides
  function testOrderWithinLimitPrice() public {
    uint limitPriceOrder1 = 6e18;

    // Calculated price will be 50/9 = 5.56
    uint fillAmount1 = 50 ether;
    uint fillAmount2 = 9 ether;

    uint assetAmount1 = 100 ether;
    uint assetAmount2 = 100 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) = _createSignedOrder(
      accountId, accountId2, limitPriceOrder1, assetAmount1, 0, 0, block.timestamp + 1 days, aliceKey, true
    );
    (Matching.LimitOrder memory order2, bytes memory signature2) = _createSignedOrder(
      accountId2, accountId, limitPriceOrder1 - 1e18, assetAmount2, 0, 0, block.timestamp + 1 days, bobKey, false
    );

    Matching.Match memory matchDetails = Matching.Match({
      amount1: fillAmount1,
      amount2: fillAmount2,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    Matching.VerifiedOrder memory order = matching.submitTrade(matchDetails, order1, order2);
    assertEq(order.asset1Amount, fillAmount1);
  }

  // Attempt to trade at price above limit for bid
  function testOrderAboveLimitPrice() public {
    uint limitPriceOrder1 = 5e18;

    // Calculated price will be 50/9 = 5.56
    uint fillAmount1 = 50 ether;
    uint fillAmount2 = 9 ether;

    uint assetAmount1 = 100 ether;
    uint assetAmount2 = 100 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) = _createSignedOrder(
      accountId, accountId2, limitPriceOrder1, assetAmount1, 0, 0, block.timestamp + 1 days, aliceKey, true
    );
    (Matching.LimitOrder memory order2, bytes memory signature2) = _createSignedOrder(
      accountId2, accountId, limitPriceOrder1, assetAmount2, 0, 0, block.timestamp + 1 days, bobKey, false
    );

    Matching.Match memory matchDetails = Matching.Match({
      amount1: fillAmount1,
      amount2: fillAmount2,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since min price is 1.1 but fillAmounts are equal == 1
    vm.expectRevert(
      abi.encodeWithSelector(
        Matching.M_BidPriceAboveLimit.selector, limitPriceOrder1, fillAmount1.divideDecimal(fillAmount2)
      )
    );
    matching.submitTrade(matchDetails, order1, order2);
  }

  // Attempt to trade at price below limit for ask
  function testOrderBelowLimitPrice() public {
    uint limitPriceOrder1 = 5e18;

    // Calculated price will be 40/10 = 4 which is less than the limit price 5
    uint fillAmount1 = 40 ether;
    uint fillAmount2 = 10 ether;

    uint assetAmount1 = 100 ether;
    uint assetAmount2 = 100 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, accountId2, 10e18, assetAmount1, 10e18, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory order2, bytes memory signature2) = _createSignedOrder(
      accountId2, accountId, limitPriceOrder1, assetAmount2, 0, 0, block.timestamp + 1 days, bobKey, false
    );

    Matching.Match memory matchDetails = Matching.Match({
      amount1: fillAmount1,
      amount2: fillAmount2,
      asset1: cashAsset,
      asset2: IAsset(address(usdc)),
      subId1: 0,
      subId2: 0,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since the calculated price is below the limit price
    vm.expectRevert(
      abi.encodeWithSelector(
        Matching.M_AskPriceBelowLimit.selector, limitPriceOrder1, fillAmount1.divideDecimal(fillAmount2)
      )
    );
    matching.submitTrade(matchDetails, order1, order2);
  }

  // Attempt to trade USDC for USDC
  function testCannotTradeSameAssets() public {
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrderAsset(accountId, accountId2, address(usdc), address(usdc), 1, 1, aliceKey, true);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrderAsset(accountId2, accountId, address(usdc), address(usdc), 1, 1, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      amount1: 1e19,
      amount2: 1e18,
      asset1: IAsset(address(usdc)),
      asset2: IAsset(address(usdc)),
      subId1: 1,
      subId2: 1,
      signature1: signature1,
      signature2: signature2
    });

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CannotTradeSameAsset.selector, address(usdc), address(usdc)));
    matching.submitTrade(matchDetails, order1, order2);
  }

  function _createSignedOrder(
    uint fromAcc,
    uint toAcc,
    uint limitPrice,
    uint assetAmount,
    uint maxFee,
    uint tradeFee,
    uint expiry,
    uint pk,
    bool isBid
  ) internal view returns (Matching.LimitOrder memory limitOrder, bytes memory signature) {
    bytes32 assetHash = matching.getAssetHash(cashAsset, IAsset(address(usdc)), 0, 0);
    Matching.OrderParams memory order1 = Matching.OrderParams({
      isBid: isBid,
      accountId: fromAcc,
      amount: assetAmount,
      limitPrice: limitPrice,
      expirationTime: expiry,
      maxFee: maxFee,
      salt: 0,
      assetHash: assetHash
    });

    // Sign the order
    bytes32 orderHash1 = matching.getOrderHash(order1);
    signature = _sign(orderHash1, pk);

    limitOrder = Matching.LimitOrder({
      isBid: order1.isBid,
      accountId1: order1.accountId,
      accountId2: toAcc,
      asset1Amount: order1.amount,
      limitPrice: order1.limitPrice,
      expirationTime: order1.expirationTime,
      maxFee: order1.maxFee,
      tradeFee: tradeFee,
      salt: order1.salt,
      assetHash: order1.assetHash
    });
  }

  function _createSignedOrderAsset(
    uint fromAcc,
    uint toAcc,
    address asset1,
    address asset2,
    uint subId1,
    uint subId2,
    uint pk,
    bool isBid
  ) internal view returns (Matching.LimitOrder memory limitOrder, bytes memory signature) {
    // Create LimitOrder
    bytes32 assetHash = matching.getAssetHash(IAsset(address(asset1)), IAsset(address(asset2)), subId1, subId2);
    Matching.OrderParams memory order1 = Matching.OrderParams({
      isBid: isBid,
      accountId: fromAcc,
      amount: 1e18,
      limitPrice: 1e18,
      expirationTime: block.timestamp + 1 days,
      maxFee: 0,
      salt: 0,
      assetHash: assetHash
    });

    // Sign the order
    bytes32 orderHash1 = matching.getOrderHash(order1);
    signature = _sign(orderHash1, pk);

    limitOrder = Matching.LimitOrder({
      isBid: order1.isBid,
      accountId1: order1.accountId,
      accountId2: toAcc,
      asset1Amount: order1.amount,
      limitPrice: order1.limitPrice,
      expirationTime: order1.expirationTime,
      maxFee: 0,
      tradeFee: 0,
      salt: order1.salt,
      assetHash: order1.assetHash
    });
  }

  function _sign(bytes32 OrderParams, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, OrderParams));
    return bytes.concat(r, s, bytes1(v));
  }
}
