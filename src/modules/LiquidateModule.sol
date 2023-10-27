// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Inherited
import {IBaseModule} from "../interfaces/IBaseModule.sol";
import {BaseModule} from "./BaseModule.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";


interface ILiquidateModule is IBaseModule {
  struct LiquidationData {
    uint liquidatedAccountId;
    uint cashTransfer;
    uint percentOfAcc;
    uint maxBidPrice;
    uint lastSeenTradeId;
    bool toNewAccount;
  }

  error TFM_InvalidFromAccount();
  error LM_InvalidLiquidateActionLength();
  error TFM_ToAccountMismatch();
}


// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract LiquidateModule is ILiquidateModule, BaseModule {
  IDutchAuction public auction;
  ICashAsset public cashAsset;

  constructor(IMatching _matching, IDutchAuction _auction) BaseModule(_matching) {
    auction = _auction;
    cashAsset = _auction.cash();
  }

  /**
   * @notice transfer asset between 2 subAccounts
   * @dev the recipient need to sign the second action as prove of ownership
   */
  function executeAction(VerifiedAction[] memory actions, bytes memory)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length != 1) revert LM_InvalidLiquidateActionLength();

    VerifiedAction memory liqAction = actions[0];
    LiquidationData memory liqData = abi.decode(actions[0], (LiquidationData));

    if (liqAction.accountId == 0) revert TFM_InvalidFromAccount();

    _checkAndInvalidateNonce(liqAction.owner, liqAction.nonce);

    address LIQUIDATED_ACCOUNT_MANAGER;

    //////
    // Create a new subaccount for the liquidator, this way we have an account with only cash.
    uint liquidatorAcc = subAccounts.createAccount(address(this), IManager(LIQUIDATED_ACCOUNT_MANAGER));

    //////
    // Transfer the cash to the liquidatorAcc
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](1);
    transferBatch[0] = ISubAccounts.AssetTransfer({
      asset: IAsset(cashAsset),
      fromAcc: liqAction.accountId,
      toAcc: liquidatorAcc,
      amount: liqData.cashTransfer
    });
    subAccounts.submitTransfers(transferBatch, bytes(0));

    //////
    // Bid on the auction
    auction.bid(
      liqData.liquidatedAccountId, liquidatorAcc, liqData.percentOfAcc, liqData.maxBidPrice, liqData.lastSeenTradeId
    );

    /////
    // Either send the subaccount back to the matching module or transfer the assets back to the original account
    if (liqData.toNewAccount) {
      newAccIds = new uint[](1);
      newAccIds[0] = liquidatorAcc;
      newAccOwners = new address[](1);
      newAccOwners[0] = actions[0].owner;
    } else {
      transferBatch[0] = ISubAccounts.AssetTransfer({
        asset: IAsset(cashAsset),
        fromAcc: liquidatorAcc,
        toAcc: liqAction.accountId,
        amount: liqData.cashTransfer
      });

      subAccounts.submitTransfers(transferBatch, bytes(0));
    }

    // Return
    _returnAccounts(actions, newAccIds);
    return (newAccIds, newAccOwners);
  }

  function _sendAllAssets(uint fromAcc, uint toAcc) internal {
    ISubAccounts.AssetBalance[] memory allBalances = subAccounts.getAccountBalances(fromAcc);

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](allBalances.length);
    for (uint i = 0; i < allBalances.length; ++i) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
        fromAcc: fromAcc,
        toAcc: toAcc,
        asset: allBalances[i].asset,
        subId: allBalances[i].subId,
        amount: allBalances[i].balance,
        assetData: bytes32(0)
      });
    }
    subAccounts.submitTransfers(transferBatch, bytes(0));
  }
}
