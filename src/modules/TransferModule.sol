// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/access/Ownable2Step.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import "../SubAccountsManager.sol";
import "../Matching.sol";
import "./BaseModule.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract TransferModule is BaseModule {
  struct TransferData {
    uint toAccountId; // not used?
    address managerForNewAccount;
    Transfers[] transfers;
  }

  struct Transfers {
    address asset;
    uint subId;
    int amount;
  }

  constructor(Matching _matching) BaseModule(_matching) {}

  /// @dev orders must be in order: [from, to]. From data field is ignored.
  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    if (orders.length != 1) revert("Invalid transfer orders length");

    // only the from order encode the detail of transfers
    TransferData memory data = abi.decode(orders[0].data, (TransferData));

    uint fromAccountId = orders[0].accountId;
    if (fromAccountId == 0) {
      revert("Transfer from account 0 not allowed");
    }

    uint toAccountId = data.toAccountId;

    // todo: make sure Matching.accountToOwner(toAccountId) is the same

    if (toAccountId == 0) {
      toAccountId = matching.accounts().createAccount(address(this), IManager(data.managerForNewAccount));
      newAccIds = new uint[](1);
      newAccIds[0] = toAccountId;
      newAccOwners = new address[](1);
      newAccOwners[0] = orders[0].owner;
    } else {
      address owner = matching.accountToOwner(toAccountId);
      if (owner != orders[0].owner) revert("Transfer must have same owner");
    }

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](data.transfers.length);
    for (uint i = 0; i < data.transfers.length; ++i) {
      // We should probably check that we aren't creating more OI by doing this transfer?
      // Users might for some reason create long and short options in different accounts for free by using this method...
      transferBatch[i] = ISubAccounts.AssetTransfer({
        asset: IAsset(data.transfers[i].asset),
        fromAcc: fromAccountId,
        toAcc: toAccountId,
        subId: data.transfers[i].subId,
        amount: data.transfers[i].amount,
        assetData: bytes32(0)
      });
    }

    matching.accounts().submitTransfers(transferBatch, "");

    // Transfer accounts back to matching
    _returnAccounts(orders, newAccIds);
  }
}
