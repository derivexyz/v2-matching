// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {IActionVerifier} from "./IActionVerifier.sol";

interface IMatching is IActionVerifier {
  function tradeExecutors(address tradeExecutor) external view returns (bool canExecute);
  function allowedModules(address tradeExecutor) external view returns (bool canExecute);

  error M_AccountNotReturned();
  error M_AccountAlreadyExists();
  error M_ArrayLengthMismatch();
  error M_OnlyAllowedModule();
  error M_OnlyTradeExecutor();
  error M_MismatchedModule();

  ////////////
  // Events //
  ////////////

  event TradeExecutorSet(address indexed executor, bool canExecute);
  event ModuleAllowed(address indexed module, bool allowed);
}
