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

  function executeAction(VerifiedOrder[] memory orders, bytes memory)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    if (orders.length != 1) revert WM_InvalidWithdrawalOrderLength();
    if (orders[0].accountId == 0) revert WM_InvalidFromAccount();

    _checkAndInvalidateNonce(orders[0].owner, orders[0].nonce);

    WithdrawalData memory data = abi.decode(orders[0].data, (WithdrawalData));

    IERC20BasedAsset(data.asset).withdraw(orders[0].accountId, data.assetAmount, orders[0].owner);

    _returnAccounts(orders, newAccIds);
    return (newAccIds, newAccOwners);
  }
}
