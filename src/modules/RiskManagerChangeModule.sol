// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {IRiskManagerChangeModule} from "../interfaces/IRiskManagerChangeModule.sol";

// Interfaces
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IMatching} from "../interfaces/IMatching.sol";

/**
 * Helper module to change manager from one to another
 */
contract RiskManagerChangeModule is IRiskManagerChangeModule, BaseModule {
  constructor(IMatching _matching) BaseModule(_matching) {}

  function executeAction(VerifiedOrder[] memory orders, bytes memory)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (orders.length != 1) revert RMCM_InvalidOrderLength();
    VerifiedOrder memory order = orders[0];
    _checkAndInvalidateNonce(order.owner, order.nonce);

    // Execute
    address newRM = abi.decode(order.data, (address));
    subAccounts.changeManager(order.accountId, IManager(newRM), new bytes(0));

    // Return
    _returnAccounts(orders, newAccIds);
    return (newAccIds, newAccOwners);
  }
}
