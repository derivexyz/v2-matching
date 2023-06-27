// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

// inherited
import {OrderVerifier} from "./OrderVerifier.sol";
import {IMatching} from "./interfaces/IMatching.sol";

// interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "./interfaces/IMatchingModule.sol";

contract Matching is IMatching, OrderVerifier {
  /// @dev Permissioned address to execute trades
  mapping(address tradeExecutor => bool canExecuteTrades) public tradeExecutors;
  mapping(address module => bool) public allowedModules;

  ///////////////
  // Functions //
  ///////////////

  constructor(ISubAccounts _accounts) OrderVerifier(_accounts) {}

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice Set which address can submit trades.
   */
  function setTradeExecutor(address tradeExecutor, bool canExecute) external onlyOwner {
    tradeExecutors[tradeExecutor] = canExecute;

    emit TradeExecutorSet(tradeExecutor, canExecute);
  }

  function setAllowedModule(address module, bool allowed) external onlyOwner {
    allowedModules[module] = allowed;

    emit ModuleAllowed(module, allowed);
  }

  /////////////////////////////
  //  Whitelisted Functions  //
  /////////////////////////////

  function verifyAndMatch(SignedOrder[] memory orders, bytes memory actionData) public onlyTradeExecutor {
    IMatchingModule module = orders[0].module;
    _verifyModule(module);

    IMatchingModule.VerifiedOrder[] memory verifiedOrders = new IMatchingModule.VerifiedOrder[](orders.length);
    for (uint i = 0; i < orders.length; i++) {
      verifiedOrders[i] = _verifyOrder(orders[i]);
    }
    _submitModuleAction(module, verifiedOrders, actionData);
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  function _submitModuleAction(
    IMatchingModule module,
    IMatchingModule.VerifiedOrder[] memory orders,
    bytes memory actionData
  ) internal {
    // Transfer accounts to the module contract
    for (uint i = 0; i < orders.length; ++i) {
      // Allow signing messages with accountId == 0, where no account needs to be transferred.
      if (orders[i].accountId == 0) continue;

      // If the account has been previously sent (orders can share accounts), skip it.
      if (subAccounts.ownerOf(orders[i].accountId) == address(module)) continue;

      subAccounts.transferFrom(address(this), address(module), orders[i].accountId);
    }

    (uint[] memory newAccIds, address[] memory newOwners) = module.executeAction(orders, actionData);

    // Ensure accounts are transferred back,
    for (uint i = 0; i < orders.length; ++i) {
      if (orders[i].accountId != 0 && subAccounts.ownerOf(orders[i].accountId) != address(this)) {
        revert M_AccountNotReturned();
      }
    }

    // Receive back a list of new subaccounts and respective owners. This allows modules to open new accounts
    if (newAccIds.length != newOwners.length) revert M_ArrayLengthMismatch();
    for (uint i = 0; i < newAccIds.length; ++i) {
      if (subAccounts.ownerOf(newAccIds[i]) != address(this)) revert M_AccountNotReturned();
      if (subAccountToOwner[newAccIds[i]] != address(0)) revert M_AccountAlreadyExists();

      subAccountToOwner[newAccIds[i]] = newOwners[i];
    }
  }

  function _verifyModule(IMatchingModule module) internal view {
    if (!allowedModules[address(module)]) {
      revert M_OnlyAllowedModule();
    }
  }

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyTradeExecutor() {
    if (!tradeExecutors[msg.sender]) revert M_OnlyTradeExecutor();
    _;
  }
}
