// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMatchingModule {
  struct VerifiedOrder {
    uint accountId;
    address owner;
    IMatchingModule module;
    bytes data;
    uint nonce;
  }

  function executeAction(VerifiedOrder[] memory orders, bytes memory actionData)
    external
    returns (uint[] memory newAccIds, address[] memory newOwners);
}
