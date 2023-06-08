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
    matching = new Matching(account, address(cashAsset), 420);

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

  // Attempt to trade an order that has expired
  function testCannotTradeIfExpired() public {
    uint expiry = block.timestamp + 1 days;
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, 1e18, 1e18, 0, expiry, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId, 1e18, 1e18, 0, expiry, aliceKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: 1e18,
      quoteAmount: 1e18,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(limitOrder1, limitOrder2, matchDetails);

    // Revert since you order has expired by a day
    vm.warp(block.timestamp + 2 days);
    vm.expectRevert(abi.encodeWithSelector(Matching.M_OrderExpired.selector, block.timestamp, expiry));
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attempt to trade 0 amount in order
  function testCannotTradeZeroAmountInOrder() public {
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, 1e18, 0, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, 1e18, 1e18, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: 1e18,
      quoteAmount: 1e18,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(limitOrder1, limitOrder2, matchDetails);

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attemp to trade 0 fill amount
  function testCannotTradeZeroAmountInMatch() public {
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, 1e18, 1e18, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, 1e18, 1e18, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: 0,
      quoteAmount: 0,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(limitOrder1, limitOrder2, matchDetails);

    // Revert since you cannot trade with 0 amount
    vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attempt to trade with yourself
  function testCannotTradeToYourself() public {
    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, 1e18, 1e18, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId, 1e18, 1e18, 0, block.timestamp + 1 days, aliceKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId,
      baseAmount: 1e18,
      quoteAmount: 1e18,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(limitOrder1, limitOrder2, matchDetails);

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CannotTradeToSelf.selector, accountId));
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attempt to fill amount more than the order
  function testCannotTradeFillAmount() public {
    uint fillAmount = 51 ether;
    uint assetAmount = 50 ether;

    (Matching.LimitOrder memory limitOrder1, bytes memory signature1) =
      _createSignedOrder(accountId, 1e18, assetAmount, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory limitOrder2, bytes memory signature2) =
      _createSignedOrder(accountId2, 1e18, assetAmount, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: fillAmount,
      quoteAmount: fillAmount,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(limitOrder1, limitOrder2, matchDetails);

    // Revert since min price is 1.1 but fillAmounts are equal == 1
    vm.expectRevert(abi.encodeWithSelector(Matching.M_InsufficientFillAmount.selector, 1, assetAmount, fillAmount));
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attempt to trade at price above limit for bid
  function testOrderAboveLimitPrice() public {
    uint limitPriceOrder1 = 99e18;

    // Calculated price will be 100 but limit is 99
    uint fillAmount1 = 1 ether;
    uint fillAmount2 = 100 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, limitPriceOrder1, 100 ether, 0, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId2, limitPriceOrder1, 100 ether, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: fillAmount1,
      quoteAmount: fillAmount2,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(order1, order2, matchDetails);

    // Revert since min price is 1.1 but fillAmounts are equal == 1
    vm.expectRevert(
      abi.encodeWithSelector(
        Matching.M_BidPriceAboveLimit.selector, limitPriceOrder1, fillAmount2.divideDecimal(fillAmount1)
      )
    );

    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attempt to trade at price below limit for ask
  function testOrderBelowLimitPrice() public {
    // Calculated price will be 40/10 = 4 which is less than the limit price of 5
    uint fillAmount1 = 10 ether;
    uint fillAmount2 = 40 ether;

    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrder(accountId, 10e18, 100 ether, 10e18, block.timestamp + 1 days, aliceKey, true);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrder(accountId2, 5e18, 100 ether, 0, block.timestamp + 1 days, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: fillAmount1,
      quoteAmount: fillAmount2,
      baseAsset: cashAsset,
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 0,
      quoteSubId: 0,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(order1, order2, matchDetails);

    // Revert since the calculated price is below the limit price
    vm.expectRevert(
      abi.encodeWithSelector(Matching.M_AskPriceBelowLimit.selector, 5e18, fillAmount2.divideDecimal(fillAmount1))
    );
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  // Attempt to trade USDC for USDC
  function testCannotTradeSameAssets() public {
    (Matching.LimitOrder memory order1, bytes memory signature1) =
      _createSignedOrderAsset(accountId, address(usdc), address(usdc), 1, 1, aliceKey, true);
    (Matching.LimitOrder memory order2, bytes memory signature2) =
      _createSignedOrderAsset(accountId2, address(usdc), address(usdc), 1, 1, bobKey, false);

    Matching.Match memory matchDetails = Matching.Match({
      bidId: accountId,
      askId: accountId2,
      baseAmount: 1e19,
      quoteAmount: 1e18,
      baseAsset: IAsset(address(usdc)),
      quoteAsset: IAsset(address(usdc)),
      baseSubId: 1,
      quoteSubId: 1,
      tradeFee: 0,
      signature1: signature1,
      signature2: signature2
    });

    (
      Matching.LimitOrder[] memory order1Array,
      Matching.LimitOrder[] memory order2Array,
      Matching.Match[] memory matchDetailsArray
    ) = _createTradeArrays(order1, order2, matchDetails);

    // Revert since you cannot trade with yourself through the Matching contract
    vm.expectRevert(abi.encodeWithSelector(Matching.M_CannotTradeSameAsset.selector, address(usdc), address(usdc)));
    matching.submitTrades(matchDetailsArray, order1Array, order2Array);
  }

  function _createSignedOrder(
    uint fromAcc,
    uint limitPrice,
    uint assetAmount,
    uint maxFee,
    uint expiry,
    uint pk,
    bool isBid
  ) internal view returns (Matching.LimitOrder memory limitOrder, bytes memory signature) {
    bytes32 instrumentHash = matching.getInstrument(cashAsset, IAsset(address(usdc)), 0, 0);
    Matching.LimitOrder memory order1 = Matching.LimitOrder({
      isBid: isBid,
      accountId1: fromAcc,
      amount: assetAmount,
      limitPrice: limitPrice,
      expirationTime: expiry,
      maxFee: maxFee,
      nonce: 0,
      instrumentHash: instrumentHash
    });

    // Sign the order
    bytes32 orderHash1 = matching.getOrderHash(order1);
    signature = _sign(orderHash1, pk);

    limitOrder = Matching.LimitOrder({
      isBid: order1.isBid,
      accountId1: order1.accountId1,
      amount: order1.amount,
      limitPrice: order1.limitPrice,
      expirationTime: order1.expirationTime,
      maxFee: order1.maxFee,
      nonce: order1.nonce,
      instrumentHash: order1.instrumentHash
    });
  }

  function _createSignedOrderAsset(
    uint fromAcc,
    address baseAsset,
    address quoteAsset,
    uint baseSubId,
    uint quoteSubId,
    uint pk,
    bool isBid
  ) internal view returns (Matching.LimitOrder memory limitOrder, bytes memory signature) {
    // Create LimitOrder
    bytes32 instrumentHash =
      matching.getInstrument(IAsset(address(baseAsset)), IAsset(address(quoteAsset)), baseSubId, quoteSubId);
    Matching.LimitOrder memory order1 = Matching.LimitOrder({
      isBid: isBid,
      accountId1: fromAcc,
      amount: 1e18,
      limitPrice: 1e18,
      expirationTime: block.timestamp + 1 days,
      maxFee: 0,
      nonce: 0,
      instrumentHash: instrumentHash
    });

    // Sign the order
    bytes32 orderHash1 = matching.getOrderHash(order1);
    signature = _sign(orderHash1, pk);

    limitOrder = Matching.LimitOrder({
      isBid: order1.isBid,
      accountId1: order1.accountId1,
      amount: order1.amount,
      limitPrice: order1.limitPrice,
      expirationTime: order1.expirationTime,
      maxFee: 0,
      nonce: order1.nonce,
      instrumentHash: order1.instrumentHash
    });
  }

  function _sign(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  function _createTradeArrays(
    Matching.LimitOrder memory order1,
    Matching.LimitOrder memory order2,
    Matching.Match memory matchDetails
  )
    internal
    pure
    returns (
      Matching.LimitOrder[] memory order1Arr,
      Matching.LimitOrder[] memory order2Arr,
      Matching.Match[] memory matchDetailsArr
    )
  {
    // Create matching arrays
    matchDetailsArr = new Matching.Match[](1);
    matchDetailsArr[0] = matchDetails;

    // Create order arrays
    order1Arr = new Matching.LimitOrder[](1);
    order1Arr[0] = order1;
    order2Arr = new Matching.LimitOrder[](1);
    order2Arr[0] = order2;
  }
}
