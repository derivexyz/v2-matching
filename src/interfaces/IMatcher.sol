// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMatcher {
  struct VerifiedOrder {
    uint accountId;
    address owner;
    IMatcher matcher;
    bytes data;
    uint nonce;
  }

  function matchOrders(VerifiedOrder[] memory orders, bytes memory matchData) external;

  ////////////
  // Events //
  ////////////
  event MatchingSet(address matching);
  event SubAccountsManagerSet(address subAccountsManager);

  ////////////
  // Errors //
  ////////////

  error M_OddArrayLength();
  error M_InvalidOwnership(address orderOwner, address accountOwner);
}
