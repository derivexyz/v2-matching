// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Libraries
import "openzeppelin/utils/math/SafeCast.sol";

// Inherited
import {BaseModule} from "./BaseModule.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";

import {IMatching} from "../interfaces/IMatching.sol";
import {ILiquidateModule} from "../interfaces/ILiquidateModule.sol";

/**
 * @title LiquidateModule
 * @dev Module to liquidate an account using the DutchAuction module
 */
contract LiquidateModule is ILiquidateModule, BaseModule {
  using SafeCast for uint;

  DutchAuction public auction;
  ICashAsset public cashAsset;

  constructor(IMatching _matching, DutchAuction _auction) BaseModule(_matching) {
    auction = _auction;
    cashAsset = _auction.cash();
  }

  /**
   * @notice Execute the signed liquidation bid
   */
  function executeAction(VerifiedAction[] memory actions, bytes memory managerData)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length != 1) revert LM_InvalidLiquidateActionLength();

    VerifiedAction memory liqAction = actions[0];
    LiquidationData memory liqData = abi.decode(actions[0].data, (LiquidationData));

    if (liqAction.subaccountId == 0) revert LM_InvalidFromAccount();

    _checkAndInvalidateNonce(liqAction.owner, liqAction.nonce);

    // Create a new subaccount for the liquidator;
    // this way we create an account with only cash, that is the same manager as the account we are liquidating
    uint liquidatorAcc = subAccounts.createAccount(address(this), subAccounts.manager(liqData.liquidatedAccountId));

    // Transfer the cash to the liquidatorAcc
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](1);
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: liqAction.subaccountId,
      toAcc: liquidatorAcc,
      asset: IAsset(cashAsset),
      subId: 0,
      amount: liqData.cashTransfer.toInt256(),
      assetData: bytes32(0)
    });
    subAccounts.submitTransfers(transferBatch, managerData);

    // Emit event for perp price for convenience
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(liqData.liquidatedAccountId);
    for (uint i = 0; i < assetBalances.length; i++) {
      // If the asset is a perp, emit the price, otherwise just ignore
      try IPerpAsset(address(assetBalances[i].asset)).getPerpPrice() returns (uint perpPrice, uint confidence) {
        emit LiquidationPerpPrice(address(assetBalances[i].asset), perpPrice, confidence);
      } catch {}
    }

    // Bid on the auction
    auction.bid(
      liqData.liquidatedAccountId, liquidatorAcc, liqData.percentOfAcc, liqData.priceLimit, liqData.lastSeenTradeId
    );

    // Either send the subaccount back to the matching module or transfer the assets back to the original account
    if (liqData.mergeAccount) {
      _transferAll(liquidatorAcc, liqAction.subaccountId);
    } else {
      newAccIds = new uint[](1);
      newAccIds[0] = liquidatorAcc;
      newAccOwners = new address[](1);
      newAccOwners[0] = actions[0].owner;
    }

    // Return
    _returnAccounts(actions, newAccIds);
    return (newAccIds, newAccOwners);
  }

  function _transferAll(uint fromId, uint toId) internal {
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(fromId);
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](assetBalances.length);
    for (uint i = 0; i < assetBalances.length; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: fromId,
        toAcc: toId,
        asset: assetBalances[i].asset,
        subId: assetBalances[i].subId,
        amount: assetBalances[i].balance,
        assetData: bytes32(0)
      });
    }
    subAccounts.submitTransfers(transfers, "");
  }
}
