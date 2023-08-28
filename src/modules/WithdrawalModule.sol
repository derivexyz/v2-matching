// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
// Interfaces
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IMatching} from "../interfaces/IMatching.sol";

contract WithdrawalModule is IWithdrawalModule, BaseModule {
  constructor(IMatching _matching) BaseModule(_matching) {}

  function executeAction(VerifiedAction[] memory actions, bytes memory)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    if (actions.length != 1) revert WM_InvalidWithdrawalActionLength();
    if (actions[0].accountId == 0) revert WM_InvalidFromAccount();

    _checkAndInvalidateNonce(actions[0].owner, actions[0].nonce);

    WithdrawalData memory data = abi.decode(actions[0].data, (WithdrawalData));

    IERC20BasedAsset(data.asset).withdraw(actions[0].accountId, data.assetAmount, actions[0].owner);

    _returnAccounts(actions, newAccIds);
    return (newAccIds, newAccOwners);
  }
}
