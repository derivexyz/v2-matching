// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMatchingModule} from "../../src/interfaces/IMatchingModule.sol";

contract BadModule is IMatchingModule {
  function executeAction(VerifiedAction[] memory actions, bytes memory)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // does not return accounts
  }

  function test() external {
    // to skip coverage
  }
}
