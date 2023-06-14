// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/Matching.sol";
import {DepositModule} from "src/modules/DepositModule.sol";
import {WithdrawalModule} from "src/modules/WithdrawalModule.sol";
import {PMRMTestBase} from "v2-core/test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

import {OrderVerifier} from "src/OrderVerifier.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract MatchingBase is PMRMTestBase {
  // SubAccounts subAccounts;

  Matching matching;
  DepositModule depositModule;
  WithdrawalModule withdrawalModule;

  // signer
  uint internal pk2;
  address internal pkOwner2;
  uint referenceTime;

  uint cashDeposit = 10000e18;

  // cannot use setup like this, cus super.setup is not overridable
  function _setUp() internal {
    // todo: update PMRMTestBase.setup
    super.setUp();
    // set signer
    pk2 = 0xBEEF;
    pkOwner2 = vm.addr(pk2);
    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;

    // Setup matching contract and modules
    matching = new Matching(subAccounts);
    depositModule = new DepositModule(matching);
    withdrawalModule = new WithdrawalModule(matching);

    _depositCash(aliceAcc, cashDeposit);
    _depositCash(bobAcc, cashDeposit);
  }

  // Creates SignedOrder with empty signature field. This order must be signed for.
  function _createUnsignedOrder(
    uint accountId,
    uint nonce,
    IMatchingModule matcher,
    bytes memory data,
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
      signature: ""
    });
  }

  // Returns the SignedOrder with signature
  function _createSignedOrder(OrderVerifier.SignedOrder memory unsigned, bytes memory signature)
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

  // function _getOrderHash(SignedOrder memory order) internal pure returns (bytes32) {
  //   return matching._getOrderHash(order);
  // }

  function _signOrder(bytes32 orderHash, uint pk) internal view returns (bytes memory) {
    bytes32 domainSeparator = matching.domainSeparator();
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  function _encodeDepositData(uint amount, address asset, address newManager) internal returns (bytes memory) {
    DepositModule.DepositData memory data =
      DepositModule.DepositData({amount: amount, asset: asset, managerForNewAccount: newManager});

    return abi.encode(data);
  }
}
