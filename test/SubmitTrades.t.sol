// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/console2.sol";
// import "v2-core/test/integration-tests/shared/IntegrationTestBase.sol";
// import {Matching} from "src/Matching.sol";
// /**
//  * @dev testing charge of OI fee in a real setting
//  */

// contract INTEGRATION_MatchingSubmitTrades is IntegrationTestBase {
//   using DecimalMath for uint;

//   Matching matching;
//   uint private immutable charlieKey;
//   uint private immutable daveKey;
//   address private immutable charlie;
//   address private immutable dave;

//   uint charlieAcc;
//   uint daveAcc;
//   int amountOfContracts = 1e18;

//   bytes32 public domainSeparator;

//   constructor() {
//     charlieKey = 0xBEEF;
//     daveKey = 0xBEEF2;
//     charlie = vm.addr(charlieKey);
//     dave = vm.addr(daveKey);
//   }

//   function setUp() public {
//     _setupIntegrationTestComplete();
//     matching = new Matching(IAccounts(accounts), address(cash), 1);
//     domainSeparator = matching.domainSeparator();
//     matching.setWhitelist(address(this), true);

//     charlieAcc = accounts.createAccount(charlie, pcrm);
//     daveAcc = accounts.createAccount(dave, pcrm);

//     // allow this contract to submit trades
//     vm.prank(charlie);
//     accounts.setApprovalForAll(address(this), true);
//     vm.prank(dave);
//     accounts.setApprovalForAll(address(this), true);

//     _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
//     _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//     _depositCash(address(charlie), charlieAcc, DEFAULT_DEPOSIT);
//     _depositCash(address(dave), daveAcc, DEFAULT_DEPOSIT);

//     vm.startPrank(charlie);
//     accounts.approve(address(matching), charlieAcc);
//     matching.openCLOBAccount(charlieAcc);
//     vm.stopPrank();
//     vm.startPrank(dave);
//     accounts.approve(address(matching), daveAcc);
//     matching.openCLOBAccount(daveAcc);
//     vm.stopPrank();
//   }

//   function testSubmitMatchedTrade() public {
//     uint callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

//     // First give Charlie the call option
//     IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
//     transferBatch[0] = IAccounts.AssetTransfer({
//       fromAcc: aliceAcc,
//       toAcc: charlieAcc,
//       asset: option,
//       subId: callId,
//       amount: amountOfContracts,
//       assetData: bytes32(0)
//     });
//     accounts.submitTransfers(transferBatch, "");

//     // Charlie trades call option for cash with dave
//     (Matching.LimitOrder memory order1, bytes memory signature1) =
//       _createSignedOrder(true, charlieAcc, 1e18, 1e18, 1 days, 0, 1, option, callId, cash, 0, charlieKey);
//     (Matching.LimitOrder memory order2, bytes memory signature2) =
//       _createSignedOrder(false, daveAcc, 10e18, 1e18, 1 days, 1e18, 1, option, callId, cash, 0, daveKey);

//     Matching.Match memory matchDetails = Matching.Match({
//       bidId: charlieAcc,
//       askId: daveAcc,
//       baseAmount: 1e18,
//       quoteAmount: 10e18,
//       baseAsset: option,
//       quoteAsset: cash,
//       baseSubId: callId,
//       quoteSubId: 0,
//       tradeFee: 0,
//       signature1: signature1,
//       signature2: signature2
//     });

//     Matching.Match[] memory matchDetailsArray = new Matching.Match[](1);
//     matchDetailsArray[0] = matchDetails;

//     Matching.LimitOrder[] memory order1Array = new Matching.LimitOrder[](1);
//     order1Array[0] = order1;
//     Matching.LimitOrder[] memory order2Array = new Matching.LimitOrder[](1);
//     order2Array[0] = order2;

//     // Check balances before the trade
//     int charlieOptionBal = accounts.getBalance(charlieAcc, option, callId);
//     int daveOptionBal = accounts.getBalance(daveAcc, option, callId);
//     assertEq(charlieOptionBal, 1e18);
//     assertEq(daveOptionBal, 0);
//     assertEq(getCashBalance(charlieAcc), int(DEFAULT_DEPOSIT - 2e18));
//     assertEq(getCashBalance(daveAcc), int(DEFAULT_DEPOSIT));
//     console2.log(getCashBalance(charlieAcc));
//     // Make the trade
//     matching.submitTrades(matchDetailsArray, order1Array, order2Array);

//     // Check balances after the trade
//     charlieOptionBal = accounts.getBalance(charlieAcc, option, callId);
//     daveOptionBal = accounts.getBalance(daveAcc, option, callId);
//     assertEq(charlieOptionBal, 0);
//     assertEq(daveOptionBal, 1e18);
//     assertEq(getCashBalance(charlieAcc), int(DEFAULT_DEPOSIT - 1e18));
//     assertEq(getCashBalance(daveAcc), int(DEFAULT_DEPOSIT - 1e18));
//     console2.log(getCashBalance(charlieAcc));
//   }

//   // function testSubmitMultipleTrades() public {
//   //   uint callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

//   //   // First give Charlie the call option
//   //   IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
//   //   transferBatch[0] = IAccounts.AssetTransfer({
//   //     fromAcc: aliceAcc,
//   //     toAcc: charlieAcc,
//   //     asset: option,
//   //     subId: callId,
//   //     amount: 2 * amountOfContracts,
//   //     assetData: bytes32(0)
//   //   });
//   //   accounts.submitTransfers(transferBatch, "");

//   //   // Charlie trades call option for cash with dave in two separate trades
//   //   (Matching.LimitOrder memory order1, bytes memory signature1) =
//   //     _createSignedOrder(charlieAcc, daveAcc, option, callId, cash, 0, 1e18, 2e18, 1e18, charlieKey, 1);
//   //   (Matching.LimitOrder memory order2, bytes memory signature2) =
//   //     _createSignedOrder(daveAcc, charlieAcc, cash, 0, option, callId, 1e18, 2e18, 1e18, daveKey, 2);

//   //   Matching.Match[] memory matchDetailsArray = new Matching.Match[](2);
//   //   matchDetailsArray[0] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});
//   //   matchDetailsArray[1] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature2, signature2: signature1});

//   //   Matching.LimitOrder[] memory order1Array = new Matching.LimitOrder[](2);
//   //   order1Array[0] = order1;
//   //   order1Array[1] = order2;
//   //   Matching.LimitOrder[] memory order2Array = new Matching.LimitOrder[](2);
//   //   order2Array[0] = order2;
//   //   order2Array[1] = order1;

//   //   // Check balances before the trades
//   //   int charlieOptionBal = accounts.getBalance(charlieAcc, option, callId);
//   //   int daveOptionBal = accounts.getBalance(daveAcc, option, callId);
//   //   assertEq(charlieOptionBal, 2e18);
//   //   assertEq(daveOptionBal, 0);

//   //   // Make the trades
//   //   matching.submitTrades(matchDetailsArray, order1Array, order2Array);

//   //   // Check balances after the trades
//   //   charlieOptionBal = accounts.getBalance(charlieAcc, option, callId);
//   //   daveOptionBal = accounts.getBalance(daveAcc, option, callId);
//   //   assertEq(charlieOptionBal, 0);
//   //   assertEq(daveOptionBal, 2e18);
//   // }

//   // function testCannotSubmitMultipleTrades() public {
//   //   uint callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

//   //   // First give Charlie the call option
//   //   IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
//   //   transferBatch[0] = IAccounts.AssetTransfer({
//   //     fromAcc: aliceAcc,
//   //     toAcc: charlieAcc,
//   //     asset: option,
//   //     subId: callId,
//   //     amount: 2 * amountOfContracts,
//   //     assetData: bytes32(0)
//   //   });
//   //   accounts.submitTransfers(transferBatch, "");

//   //   // Charlie trades call option for cash with dave in two separate trades
//   //   (Matching.LimitOrder memory order1, bytes memory signature1) =
//   //     _createSignedOrder(charlieAcc, daveAcc, option, callId, cash, 0, 1e18, 2e18, 1e18, charlieKey, 1);
//   //   (Matching.LimitOrder memory order2, bytes memory signature2) =
//   //     _createSignedOrder(daveAcc, charlieAcc, cash, 0, option, callId, 1e18, 2e18, 1e18, daveKey, 2);

//   //   Matching.Match[] memory matchDetailsArray = new Matching.Match[](3);
//   //   matchDetailsArray[0] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});
//   //   matchDetailsArray[1] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature2, signature2: signature1});

//   //   // Insufficient fill for this match
//   //   matchDetailsArray[2] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});

//   //   Matching.LimitOrder[] memory order1Array = new Matching.LimitOrder[](3);
//   //   order1Array[0] = order1;
//   //   order1Array[1] = order2;
//   //   order1Array[2] = order1;
//   //   Matching.LimitOrder[] memory order2Array = new Matching.LimitOrder[](3);
//   //   order2Array[0] = order2;
//   //   order2Array[1] = order1;
//   //   order2Array[2] = order2;

//   //   // Should revert
//   //   vm.expectRevert(abi.encodeWithSelector(Matching.M_InsufficientFillAmount.selector, 1, 0, 1e18));
//   //   matching.submitTrades(matchDetailsArray, order1Array, order2Array);
//   // }

//   // function testCannotSubmitMultipleTradesZeroAmount() public {
//   //   uint callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

//   //   // First give Charlie the call option
//   //   IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
//   //   transferBatch[0] = IAccounts.AssetTransfer({
//   //     fromAcc: aliceAcc,
//   //     toAcc: charlieAcc,
//   //     asset: option,
//   //     subId: callId,
//   //     amount: 2 * amountOfContracts,
//   //     assetData: bytes32(0)
//   //   });
//   //   accounts.submitTransfers(transferBatch, "");

//   //   // Charlie trades call option for cash with dave in two separate trades
//   //   (Matching.LimitOrder memory order1, bytes memory signature1) =
//   //     _createSignedOrder(charlieAcc, daveAcc, option, callId, cash, 0, 1e18, 0, 0, charlieKey, 1);
//   //   (Matching.LimitOrder memory order2, bytes memory signature2) =
//   //     _createSignedOrder(daveAcc, charlieAcc, cash, 0, option, callId, 1e18, 0, 0, daveKey, 2);

//   //   Matching.Match[] memory matchDetailsArray = new Matching.Match[](2);
//   //   matchDetailsArray[0] = Matching.Match({amount1: 0, amount2: 0, signature1: signature1, signature2: signature2});
//   //   matchDetailsArray[1] = Matching.Match({amount1: 0, amount2: 0, signature1: signature2, signature2: signature1});

//   //   Matching.LimitOrder[] memory order1Array = new Matching.LimitOrder[](2);
//   //   order1Array[0] = order1;
//   //   order1Array[1] = order2;
//   //   Matching.LimitOrder[] memory order2Array = new Matching.LimitOrder[](2);
//   //   order2Array[0] = order2;
//   //   order2Array[1] = order1;

//   //   // Should revert
//   //   vm.expectRevert(Matching.M_ZeroAmountToTrade.selector);
//   //   matching.submitTrades(matchDetailsArray, order1Array, order2Array);
//   // }

//   // function testFreezeAccount() public {
//   //   uint callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

//   //   // First give Charlie the call option
//   //   IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
//   //   transferBatch[0] = IAccounts.AssetTransfer({
//   //     fromAcc: aliceAcc,
//   //     toAcc: charlieAcc,
//   //     asset: option,
//   //     subId: callId,
//   //     amount: 2 * amountOfContracts,
//   //     assetData: bytes32(0)
//   //   });
//   //   accounts.submitTransfers(transferBatch, "");

//   //   // Charlie trades call option for cash with dave in two separate trades
//   //   (Matching.LimitOrder memory order1, bytes memory signature1) =
//   //     _createSignedOrder(charlieAcc, daveAcc, option, callId, cash, 0, 1e18, 2e18, 1e18, charlieKey, 1);
//   //   (Matching.LimitOrder memory order2, bytes memory signature2) =
//   //     _createSignedOrder(daveAcc, charlieAcc, cash, 0, option, callId, 1e18, 2e18, 1e18, daveKey, 2);

//   //   Matching.Match[] memory matchDetailsArray = new Matching.Match[](2);
//   //   matchDetailsArray[0] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});
//   //   matchDetailsArray[1] =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature2, signature2: signature1});

//   //   Matching.LimitOrder[] memory order1Array = new Matching.LimitOrder[](2);
//   //   order1Array[0] = order1;
//   //   order1Array[1] = order2;
//   //   Matching.LimitOrder[] memory order2Array = new Matching.LimitOrder[](2);
//   //   order2Array[0] = order2;
//   //   order2Array[1] = order1;

//   //   // Freeze Dave's account should revert the order
//   //   vm.startPrank(dave);
//   //   matching.freezeAccount(true);
//   //   vm.stopPrank();

//   //   // Should revert
//   //   vm.expectRevert(abi.encodeWithSelector(Matching.M_AccountFrozen.selector, dave));
//   //   matching.submitTrades(matchDetailsArray, order1Array, order2Array);
//   // }

//   // function testFillTwoOrdersAgainstOne() public {
//   //   uint callId = option.getSubId(block.timestamp + 4 weeks, 2000e18, true);

//   //   // First give Charlie the call option
//   //   IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](1);
//   //   transferBatch[0] = IAccounts.AssetTransfer({
//   //     fromAcc: aliceAcc,
//   //     toAcc: charlieAcc,
//   //     asset: option,
//   //     subId: callId,
//   //     amount: 2 * amountOfContracts,
//   //     assetData: bytes32(0)
//   //   });
//   //   accounts.submitTransfers(transferBatch, "");

//   //   // First order fills half charlie amount
//   //   (Matching.LimitOrder memory order1, bytes memory signature1) =
//   //     _createSignedOrder(charlieAcc, daveAcc, option, callId, cash, 0, 1e18, 2e18, 1e18, charlieKey, 1);
//   //   (Matching.LimitOrder memory order2, bytes memory signature2) =
//   //     _createSignedOrder(daveAcc, charlieAcc, cash, 0, option, callId, 1e18, 1e18, 1e18, daveKey, 2);
//   //   Matching.Match memory firstOrder =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature2});
//   //   matching.submitTrade(firstOrder, order1, order2);

//   //   // Second order fills the rest of charlies amount
//   //   (Matching.LimitOrder memory order3, bytes memory signature3) =
//   //     _createSignedOrder(daveAcc, charlieAcc, cash, 0, option, callId, 1e18, 1e18, 1e18, daveKey, 3);
//   //   Matching.Match memory secondOrder =
//   //     Matching.Match({amount1: 1e18, amount2: 1e18, signature1: signature1, signature2: signature3});
//   //   matching.submitTrade(secondOrder, order1, order3);
//   // }

//   function _createSignedOrder(
//     bool isBid,
//     uint accountId1,
//     uint amount,
//     uint limitPrice,
//     uint secsToExpire,
//     uint maxFee,
//     uint nonce,
//     IAsset asset1,
//     uint subId1,
//     IAsset asset2,
//     uint subId2,
//     uint pk
//   ) internal view returns (Matching.LimitOrder memory order, bytes memory signature) {
//     bytes32 instrumentHash = matching.getInstrument(asset1, asset2, subId1, subId2);
    
//     // Create LimitOrder
//     order = Matching.LimitOrder({
//       isBid: isBid,
//       accountId1: accountId1,
//       amount: amount,
//       limitPrice: limitPrice,
//       expirationTime: block.timestamp + secsToExpire,
//       maxFee: maxFee,
//       nonce: nonce,
//       instrumentHash: instrumentHash
//     });

//     // Sign the order
//     bytes32 orderHash = matching.getOrderHash(order);
//     signature = _sign(orderHash, pk);
//   }

//   function _sign(bytes32 OrderParams, uint pk) internal view returns (bytes memory) {
//     (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, OrderParams));
//     return bytes.concat(r, s, bytes1(v));
//   }
// }
