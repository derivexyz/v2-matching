// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMatchingModule {
  struct VerifiedAction {
    uint subaccountId;
    address owner;
    IMatchingModule module;
    bytes data;
    uint nonce;
  }

  function executeAction(VerifiedAction[] memory actions, bytes memory actionData)
    external
    returns (uint[] memory newAccIds, address[] memory newOwners);
}
