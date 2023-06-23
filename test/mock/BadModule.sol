// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMatchingModule} from "../../src/interfaces/IMatchingModule.sol";

contract BadModule is IMatchingModule {
  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // does not return accounts
  }
}
