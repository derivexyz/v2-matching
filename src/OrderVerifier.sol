// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "v2-core/src/SubAccounts.sol";
import "./interfaces/IMatcher.sol";

contract OrderVerifier is HashingLogic, Ownable2Step {
  HashingLogic public hashing;

  // (accountID, signer, nonce) must be unique
  struct SignedOrder {
    uint accountId;
    uint nonce;
    IMatcher matcher;
    bytes data; // todo will data here follow EIP712 structured hash standard?
    uint expiry;
    bytes signature;
    address signer;
  }

  /**
   * @notice Set which address can submit trades.
   */
  function setHashingLogic(HashingLogic _hashing) external onlyOwner {
    hashing = _hashing;

    emit SubAccountsSet(address(_hashing));
  }

  function _verifyOrder(SignedOrder memory order, IMatcher matcher) internal returns (IMatcher.VerifiedOrder memory) {
    // TODO: check signature, nonce, expiry. Make sure no repeated nonce. Limits are handled by the matchers.
    if (order.expiry > block.timestamp) revert M_OrderExpired();
    hashing._verifySignature(order.accountId, order.data, order.signature);

    return IMatcher.VerifiedOrder({
      accountId: order.accountId,
      owner: address(0),
      matcher: order.matcher,
      data: order.data,
      nonce: order.nonce
    });
  }
}
