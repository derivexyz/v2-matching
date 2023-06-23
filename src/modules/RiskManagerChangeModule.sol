// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IManager} from "v2-core/src/interfaces/IManager.sol";
import "./BaseModule.sol";

/**
 * Helper module to change manager from one to another
 */
contract RiskManagerChangeModule is BaseModule {
  error RMCM_InvalidOrderLength();

  constructor(Matching _matching) BaseModule(_matching) {}

  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    if (orders.length != 1) revert RMCM_InvalidOrderLength();

    address newRM = abi.decode(orders[0].data, (address));
    accounts.changeManager(orders[0].accountId, IManager(newRM), new bytes(0));

    _returnAccounts(orders, newAccIds);
  }
}
