// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import "./BaseModule.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract RiskManagerChangeModule is BaseModule {
  struct RMChangeData {
    address newRM;
  }

  constructor(Matching _matching) BaseModule(_matching) {}

  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    returns (uint[] memory accountIds, address[] memory owners)
  {
    for (uint i = 0; i < orders.length; ++i) {
      RMChangeData memory data = abi.decode(orders[i].data, (RMChangeData));
      // TODO: change risk manager
    }
  }
}
