// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/access/Ownable2Step.sol";
import "v2-core/src/SubAccounts.sol";
import "../interfaces/IMatcher.sol";
import "../SubAccountsManager.sol";
import "../Matching.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract TransferModule is IMatcher, Ownable2Step {
  Matching public matching;

  struct TransferData {
    uint toAccountId;
    Transfers[] transfers;
  }

  struct Transfers {
    address asset;
    uint subId;
    int amount;
  }

  /**
   * @notice Set SubAccountManager
   */
  function setMatching(Matching _matching) external onlyOwner {
    manager = _matching;

    emit MatchingSet(address(_matching));
  }

  /// @dev orders must be in order: [to, from]
  function matchOrders(VerifiedOrder[] memory orders, bytes memory) public {
    if (orders.length % 2 == 1) revert M_OddArrayLength();

    TransferData[] memory data = new TransferData[](orders.length);
    for (uint i = 0; i < orders.length; ++i) {
      data[i] = abi.decode(orders[i].data, (TransferData));
    }

    // TODO: verify owner of both subaccounts is the same => also both have to be approved so we cant do this loop
    _verifyOwners(orders, data);

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](data.transfers.length);
    for (uint i = 0; i < data.transfers.length; ++i) {
      // We should probably check that we aren't creating more OI by doing this transfer?
      // Users might for some reason create long and short options in different accounts for free by using this method...

      transferBatch[i] = ISubAccounts.AssetTransfer({
        asset: IAsset(data.transfers[i].asset),
        fromAcc: orders[i].accountId,
        toAcc: data.toAccountId,
        subId: data.transfers[i].subId,
        amount: data.transfers[i].amount,
        assetData: bytes32(0)
      });
    }

    manger.accounts.submitTransfers(transferBatch, "");

    // Transfer accounts back to matching
    _transferAccounts(orders);
  }

  function _verifyOwners(VerifiedOrder[] memory orders, TransferData[] memory data) internal {
    for (uint i = 0; i < orders.length; i++) {
      address orderOwner = matching.accounts.ownerOf(orders[i].accountId);
      address toAccountOwner = matching.accounts.ownerOf(data[i].toAccountId);

      if (orderOwner != toAccountOwner) {
        revert M_InvalidOwnership(orderOwner, toAccountOwner);
      }
    }
  }

  function _transferAccounts(VerifiedOrder[] memory orders) internal {
    for (uint i = 0; orders.legnth;) {
      mangager.accounts.transferFrom(address(this), address(matching), orders[i].accountId);
      unchecked {
        i++;
      }
    }
  }
}
