// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {StandardManager} from "v2-core/src/risk-managers/StandardManager.sol";
import {PMRM, IPMRM} from "v2-core/src/risk-managers/PMRM.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {IPMRM_2} from "v2-core/src/interfaces/IPMRM_2.sol";
import {PMRM_2} from "v2-core/src/risk-managers/PMRM_2.sol";

/**
 * @title LyraAuctionUtils
 * @dev Contract to help with liquidating accounts that are under auction. Adds convenience functions to help with
 * combining some of the steps needed to complete an auction, including flagging and creating temporary subaccounts.
 * To help with flagging, there is a getMM function which also returns the worstScenario.
 * For bidding the following combinations of options are possible:
 * - submit data before interacting (yes or no)
 * - create new subaccount which takes cash from liquidator account (yes only)
 * - bid with new subaccount (yes only)
 * - merge subaccount back into liquidator account (yes or no)
 */
contract LyraAuctionUtils {
  ISubAccounts subAccounts;
  DutchAuction auction;
  address cash;
  address srm;

  error LAU_NotOwner();

  constructor(ISubAccounts _subAccounts, DutchAuction _auction, address _srm) {
    subAccounts = _subAccounts;
    auction = _auction;
    cash = address(auction.cash());
    srm = _srm;
  }

  function getMM(uint subId) external view returns (address manager, int mm, int mtm, uint worstScenario) {
    manager = address(subAccounts.manager(subId));

    if (manager == srm) {
      (mm, mtm) = StandardManager(manager).getMarginAndMarkToMarket(subId, false, 0);
      return (manager, mm, mtm, 0);
    }

    {
      bytes memory callData = abi.encodeWithSelector(PMRM(manager).arrangePortfolio.selector, subId);
      (bool ok, bytes memory result) = manager.staticcall(callData);

      if (ok) {
        IPMRM.Portfolio memory p = abi.decode(result, (IPMRM.Portfolio));
        (mm, mtm, worstScenario) =
        PMRM(manager).lib().getMarginAndMarkToMarket(p, false, PMRM(manager).getScenarios());
        return (manager, mm, mtm, worstScenario);
      }
    }

    IPMRM_2.Portfolio memory p2 = PMRM_2(manager).arrangePortfolio(subId);
    (mm, mtm, worstScenario) =
    PMRM_2(manager).lib().getMarginAndMarkToMarket(p2, false, PMRM_2(manager).getScenarios());

    return (manager, mm, mtm, worstScenario);
  }

  function startInsolventAuction(uint accountId, uint worstScenario) external {
    if (auction.isAuctionLive(accountId)) {
      auction.terminateAuction(accountId);
    }
    auction.startAuction(accountId, worstScenario);
  }

  function advancedBid(
    uint worstScenarioId,
    uint accountId,
    uint bidderId,
    uint percentOfAccount,
    int priceLimit,
    uint expectedLastTradeId,
    uint collateralAmount,
    bool mergeAccountBack,
    bytes memory managerData
  ) external returns (uint newBidder) {
    if (subAccounts.ownerOf(bidderId) != msg.sender) {
      revert LAU_NotOwner();
    }

    if (!auction.isAuctionLive(accountId)) {
      auction.startAuction(accountId, worstScenarioId);
    }

    newBidder = _bidWithNewAccount(
      accountId, bidderId, percentOfAccount, priceLimit, expectedLastTradeId, collateralAmount, managerData
    );

    if (mergeAccountBack) {
      _transferAll(newBidder, bidderId);
    }

    // even if empty, we just transfer the subaccount back to the liquidator
    subAccounts.transferFrom(address(this), msg.sender, newBidder);
  }

  function _bidWithNewAccount(
    uint accountId,
    uint bidderId,
    uint percentOfAccount,
    int priceLimit,
    uint expectedLastTradeId,
    uint cashAmount,
    bytes memory managerData
  ) internal returns (uint newBidder) {
    // Create a new subaccount
    newBidder = subAccounts.createAccount(address(this), subAccounts.manager(accountId));

    // Move the cash needed for bidding and collateral into
    _transferCash(bidderId, newBidder, cashAmount, managerData);

    // Bid with the new subaccount
    auction.bid(accountId, newBidder, percentOfAccount, priceLimit, expectedLastTradeId);
  }

  function _transferCash(uint fromId, uint toId, uint amount, bytes memory managerData) internal {
    ISubAccounts.AssetTransfer memory adjustment = ISubAccounts.AssetTransfer({
      fromAcc: fromId,
      toAcc: toId,
      asset: IAsset(cash),
      subId: 0,
      amount: int(amount),
      assetData: bytes32(0)
    });
    subAccounts.submitTransfer(adjustment, managerData);
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
