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

  function executeAction(VerifiedAction[] memory actions, bytes memory)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length != 1) revert RMCM_InvalidActionLength();
    VerifiedAction memory action = actions[0];
    _checkAndInvalidateNonce(action.owner, action.nonce);

    // Execute
    address newRM = abi.decode(action.data, (address));
    subAccounts.changeManager(action.accountId, IManager(newRM), new bytes(0));

    // Return
    _returnAccounts(actions, newAccIds);
    return (newAccIds, newAccOwners);
  }
}
