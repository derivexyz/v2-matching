// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {ITransferModule} from "../interfaces/ITransferModule.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IMatching} from "../interfaces/IMatching.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract TransferModule is ITransferModule, BaseModule {
  constructor(IMatching _matching) BaseModule(_matching) {}

  /**
   * @notice transfer asset between 2 subAccounts
   * @dev the recipient need to sign the second action as prove of ownership
   */
  function executeAction(VerifiedAction[] memory actions, bytes memory managerData)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length != 2) revert TFM_InvalidTransferActionLength();
    VerifiedAction memory fromAction = actions[0];
    VerifiedAction memory toAction = actions[1];

    if (fromAction.owner != toAction.owner) revert TFM_InvalidRecipientOwner();
    if (fromAction.accountId == 0) revert TFM_InvalidFromAccount();

    _checkAndInvalidateNonce(fromAction.owner, fromAction.nonce);
    _checkAndInvalidateNonce(toAction.owner, toAction.nonce);

    // note: only the from order needs to encode the detail of transfers
    TransferData memory transferData = abi.decode(fromAction.data, (TransferData));

    uint toAccountId = transferData.toAccountId;
    if (toAction.accountId != toAccountId) revert TFM_ToAccountMismatch();

    // Create the account if accountId 0 is used
    if (toAccountId == 0) {
      toAccountId = subAccounts.createAccount(address(this), IManager(transferData.managerForNewAccount));
      newAccIds = new uint[](1);
      newAccIds[0] = toAccountId;
      newAccOwners = new address[](1);
      newAccOwners[0] = actions[0].owner;
    }

    // Execute
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](transferData.transfers.length);
    for (uint i = 0; i < transferData.transfers.length; ++i) {
      // Note: this transfer could potentially increase OI (transfer when balance == 0) so this should be checked by the
      // trusted trade executors.
      transferBatch[i] = ISubAccounts.AssetTransfer({
        asset: IAsset(transferData.transfers[i].asset),
        fromAcc: fromAction.accountId,
        toAcc: toAccountId,
        subId: transferData.transfers[i].subId,
        amount: transferData.transfers[i].amount,
        assetData: bytes32(0)
      });
    }

    subAccounts.submitTransfers(transferBatch, managerData);

    // Return
    _returnAccounts(actions, newAccIds);
    return (newAccIds, newAccOwners);
  }
}
