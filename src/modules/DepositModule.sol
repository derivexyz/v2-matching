// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";

import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import "./BaseModule.sol";
// import "../interfaces/IERC20BasedAsset.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract DepositModule is BaseModule {
  struct DepositData {
    uint amount;
    address asset;
    address managerForNewAccount;
  }

  constructor(Matching _matching) BaseModule(_matching) {}

  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    if (orders.length != 1) revert("Invalid deposit orders length");

    _checkAndInvalidateNonce(orders[0].owner, orders[0].nonce);

    DepositData memory data = abi.decode(orders[0].data, (DepositData));
    uint accountId = orders[0].accountId;
    if (accountId == 0) {
      accountId = matching.accounts().createAccount(address(this), IManager(data.managerForNewAccount));
      console2.log("accountId", accountId);

      // Return new accountId with owner
      newAccIds = new uint[](1);
      newAccIds[0] = accountId;
      newAccOwners = new address[](1);
      newAccOwners[0] = orders[0].owner;
    }

    IERC20Metadata depositToken = IERC20BasedAsset(data.asset).wrappedAsset();
    depositToken.transferFrom(orders[0].owner, address(this), data.amount);

    depositToken.approve(address(data.asset), data.amount);
    IERC20BasedAsset(data.asset).deposit(accountId, data.amount);

    _returnAccounts(orders, newAccIds);
  }
}
