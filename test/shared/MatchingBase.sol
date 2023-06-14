// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/Matching.sol";
import "v2-core-test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract MatchingBase is PMRMTestBase {
  // SubAccounts subAccounts;

  Matching matching;
  DepositModule depositModule;
  WithdrawalsModule withdrawalModule;

  // signer
  uint private pk;
  address private pkOwner;
  uint referenceTime;

  uint cashDeposit = 10000e18;

  function setUp() public {
    super.setUp();
    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);
    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;

    // Setup matching contract and modules
    matching = new Matching(subAccounts);
    depositModule = new DepositModule(matching);
    withdrawalModule = new WithdrawalsModule(matching);

    _depositCash(aliceAcc, cashDeposit);
    _depositCash(bobAcc, cashDeposit);
  }

  // Creates SignedOrder with empty signature field. This order must be signed for.
  function _createUnsignedOrder(
    uint accountId,
    uint nonce,
    IMatchingModule matcher,
    bytes data,
    uint expiry,
    address signer
  ) internal returns (OrderVerifier.SignedOrder memory order) {
    order = OrderVerifier.SignedOrder({
      accountId: accountId,
      nonce: nonce,
      matcher: matcher,
      data: data,
      expiry: expiry,
      signer: signer,
      signature: 0
    });
  }

  // Returns the SignedOrder with signature
  function _createSignedOrder(OrderVerifier.SignedOrder memory unsigned, bytes signature)
    internal
    returns (OrderVerifier.SignedOrder memory order)
  {
    order = OrderVerifier.SignedOrder({
      accountId: unsigned.accountId,
      nonce: unsigned.nonce,
      matcher: unsigned.matcher,
      data: unsigned.data,
      expiry: unsigned.expiry,
      signer: unsigned.signer,
      signature: signature
    });
  }

  function _getOrderHash(SignedOrder memory order) internal pure returns (bytes32) {
    return matching._getOrderHash(order);
  }

  function _signOrder(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
