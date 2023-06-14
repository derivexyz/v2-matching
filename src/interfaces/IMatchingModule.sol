// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMatchingModule {
  struct VerifiedOrder {
    uint accountId;
    address owner;
    IMatchingModule matcher;
    bytes data;
    uint nonce;
  }

  function matchOrders(VerifiedOrder[] memory orders, bytes memory matchData)
    external
    returns (uint[] memory newAccIds, address[] memory newOwners);
}
