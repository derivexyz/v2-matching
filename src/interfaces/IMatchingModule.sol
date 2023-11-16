// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

interface IMatchingModule {
  struct VerifiedAction {
    uint subaccountId;
    address owner;
    IMatchingModule module;
    bytes data;
    uint nonce;
  }

  /**
   * @notice Execute a list of actions
   * @dev This function is called by the trade executor
   * @param actions List of signed actions to execute
   * @param actionData Arbitrary data to pass to the module
   */
  function executeAction(VerifiedAction[] memory actions, bytes memory actionData)
    external
    returns (uint[] memory newAccIds, address[] memory newOwners);
}
