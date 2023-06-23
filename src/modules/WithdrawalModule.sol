// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import "./BaseModule.sol";

interface IWithdrawableAsset {
  function withdraw(uint accountId, uint assetAmount, address recipient) external;
}

contract WithdrawalModule is BaseModule {
  struct WithdrawalData {
    address asset;
    uint assetAmount;
  }

  error WM_InvalidWithdrawalOrderLength();
  error WM_InvalidFromAccount();

  constructor(Matching _matching) BaseModule(_matching) {}

  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    if (orders.length != 1) revert WM_InvalidWithdrawalOrderLength();
    if (orders[0].accountId == 0) revert WM_InvalidFromAccount();

    _checkAndInvalidateNonce(orders[0].owner, orders[0].nonce);

    WithdrawalData memory data = abi.decode(orders[0].data, (WithdrawalData));

    IWithdrawableAsset(data.asset).withdraw(orders[0].accountId, data.assetAmount, orders[0].owner);

    _returnAccounts(orders, newAccIds);
  }
}
