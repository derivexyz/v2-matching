// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Inherited
import {ActionVerifier} from "./ActionVerifier.sol";
import {IMatching} from "./interfaces/IMatching.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "./interfaces/IMatchingModule.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract Matching is IMatching, ActionVerifier {
  /// @dev Permissioned address to execute trades
  mapping(address tradeExecutor => bool canExecuteTrades) public tradeExecutors;

  /// @dev Permissioned modules to be invoked
  mapping(address module => bool) public allowedModules;

  constructor(ISubAccounts _accounts) ActionVerifier(_accounts) {}

  ////////////////////////////
  //       Owner-only       //
  ////////////////////////////

  /**
   * @notice Set which address can submit trades.
   */
  function setTradeExecutor(address tradeExecutor, bool canExecute) external onlyOwner {
    tradeExecutors[tradeExecutor] = canExecute;

    emit TradeExecutorSet(tradeExecutor, canExecute);
  }

  /**
   * @dev Set an action module to be allowed or disallowed
   */
  function setAllowedModule(address module, bool allowed) external onlyOwner {
    allowedModules[module] = allowed;

    emit ModuleAllowed(module, allowed);
  }

  /**
   * @dev This contract should never hold any funds, but just in case, allow the owner to withdraw
   */
  function withdrawERC20(address token, address recipient, uint amount) external onlyOwner {
    IERC20(token).transfer(recipient, amount);
  }

  /////////////////////////////
  //    Guarded Functions    //
  /////////////////////////////

  function verifyAndMatch(Action[] memory actions, bytes[] memory signatures, bytes memory actionData)
    public
    onlyTradeExecutor
  {
    IMatchingModule module = actions[0].module;

    if (!allowedModules[address(module)]) revert M_OnlyAllowedModule();
    if (actions.length != signatures.length) revert M_ArrayLengthMismatch();

    IMatchingModule.VerifiedAction[] memory verifiedActions = new IMatchingModule.VerifiedAction[](actions.length);
    for (uint i = 0; i < actions.length; i++) {
      if (actions[i].module != module) revert M_MismatchedModule();
      verifiedActions[i] = _verifyAction(actions[i], signatures[i]);
    }
    _submitModuleAction(module, verifiedActions, actionData);
  }

  /////////////////////////////
  //    Internal Functions   //
  /////////////////////////////

  /**
   * @notice sent array of signed actions to the module contract
   * @dev expect the module to transfer the ownership back to Matching.sol at the end
   */
  function _submitModuleAction(
    IMatchingModule module,
    IMatchingModule.VerifiedAction[] memory actions,
    bytes memory actionData
  ) internal {
    // Transfer accounts to the module contract
    for (uint i = 0; i < actions.length; ++i) {
      // Allow signing messages with accountId == 0, where no account needs to be transferred.
      if (actions[i].subaccountId == 0) continue;

      // If the account has been previously sent (actions can share accounts), skip it.
      if (subAccounts.ownerOf(actions[i].subaccountId) == address(module)) continue;

      subAccounts.transferFrom(address(this), address(module), actions[i].subaccountId);
    }

    (uint[] memory newAccIds, address[] memory newOwners) = module.executeAction(actions, actionData);

    // Ensure accounts are transferred back,
    for (uint i = 0; i < actions.length; ++i) {
      if (actions[i].subaccountId != 0 && subAccounts.ownerOf(actions[i].subaccountId) != address(this)) {
        revert M_AccountNotReturned();
      }
    }

    // Receive back a list of new subaccounts and respective owners. This allows modules to open new accounts
    if (newAccIds.length != newOwners.length) revert M_ArrayLengthMismatch();
    for (uint i = 0; i < newAccIds.length; ++i) {
      if (subAccounts.ownerOf(newAccIds[i]) != address(this)) revert M_AccountNotReturned();
      if (subAccountToOwner[newAccIds[i]] != address(0)) revert M_AccountAlreadyExists();

      subAccountToOwner[newAccIds[i]] = newOwners[i];
      emit DepositedSubAccount(newAccIds[i], newOwners[i]);
    }
  }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyTradeExecutor() {
    if (!tradeExecutors[msg.sender]) revert M_OnlyTradeExecutor();
    _;
  }
}
