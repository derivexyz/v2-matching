// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Libraries
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {IRfqModule} from "../interfaces/IRfqModule.sol";

// Interfaces
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {IDataReceiver} from "v2-core/src/interfaces/IDataReceiver.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IMatching} from "../interfaces/IMatching.sol";

import "forge-std/console2.sol";

/**
 * @title RfqModule
 * @dev Allows a user to request a bundle of trades to all be executed atomically
 */
contract RfqModule is IRfqModule, BaseModule {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  // @dev we fix the quoteAsset for the contracts so we only support one quoteAsset per deployment
  IAsset public immutable quoteAsset;

  mapping(IPerpAsset => bool) public isPerpAsset;

  uint public feeRecipient;

  constructor(IMatching _matching, IAsset _quoteAsset, uint _feeRecipient) BaseModule(_matching) {
    quoteAsset = _quoteAsset;
    feeRecipient = _feeRecipient;
  }

  ////////////////////
  //   Owner-Only   //
  ////////////////////

  /**
   * @dev set fee recipient account
   */
  function setFeeRecipient(uint _feeRecipient) external onlyOwner {
    feeRecipient = _feeRecipient;
  }

  /**
   * @dev set perp asset mapping
   */
  function setPerpAsset(IPerpAsset _perpAsset, bool isPerp) external onlyOwner {
    isPerpAsset[_perpAsset] = isPerp;
  }

  ////////////////////////
  //   Action Handler   //
  ////////////////////////

  /**
   * @dev Assumes VerifiedActions are sorted in the order: [requesterAction, takerActions]
   * @param actions The actions to execute
   * @param actionDataBytes The data to pass to the module by the executor. Expected to be OrderData
   */
  function executeAction(VerifiedAction[] memory actions, bytes memory actionDataBytes)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length != 2) revert RFQM_InvalidActionsLength();

    // Maker (user placing RFQ order) is always receiving the assets from the taker (user filling order)
    VerifiedAction memory makerAction = actions[0];
    VerifiedAction memory takerAction = actions[1];

    _checkAndInvalidateNonce(makerAction.owner, makerAction.nonce);
    _checkAndInvalidateNonce(takerAction.owner, takerAction.nonce);

    OrderData memory order = abi.decode(actionDataBytes, (OrderData));

    RfqOrder memory makerOrder = abi.decode(actions[0].data, (RfqOrder));
    TakerOrder memory takerOrder = abi.decode(actions[1].data, (TakerOrder));

    if (makerAction.subaccountId != order.makerAccount || takerAction.subaccountId != order.takerAccount) {
      revert RFQM_SignedAccountMismatch();
    }

    if (makerOrder.maxFee < order.makerFee || takerOrder.maxFee < order.takerFee) {
      revert RFQM_FeeTooHigh();
    }

    if (takerOrder.orderHash != keccak256(actions[0].data)) revert RFQM_InvalidTakerHash();

    // Update feeds in advance, so perpPrice is up to date before we use it for the trade
    _processManagerData(order.managerData);

    // Total transfers = number of assets + 3 (cash transfer, maker fee, taker fee)
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](makerOrder.trades.length + 3);

    int totalCashTransfer = 0;

    // Iterate over the trades in the order and sum total cash to transfer
    for (uint i = 0; i < makerOrder.trades.length; i++) {
      TradeData memory tradeData = makerOrder.trades[i];

      if (_isPerp(tradeData.asset)) {
        int perpDelta = _getPerpDelta(tradeData.asset, tradeData.markPrice);
        totalCashTransfer += perpDelta.multiplyDecimal(tradeData.amount);
      } else {
        totalCashTransfer += tradeData.markPrice.multiplyDecimal(tradeData.amount);
      }

      transferBatch[i] = ISubAccounts.AssetTransfer({
        asset: IAsset(tradeData.asset),
        subId: tradeData.subId,
        amount: tradeData.amount,
        fromAcc: order.takerAccount,
        toAcc: order.makerAccount,
        assetData: bytes32(0)
      });
    }

    // Transfer the total payment for the order
    transferBatch[transferBatch.length - 3] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: totalCashTransfer,
      fromAcc: order.makerAccount,
      toAcc: order.takerAccount,
      assetData: bytes32(0)
    });

    // Transfer the fee from the maker
    transferBatch[transferBatch.length - 2] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: order.makerFee.toInt256(),
      fromAcc: order.makerAccount,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });

    // Transfer the fee from the taker
    transferBatch[transferBatch.length - 1] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: order.takerFee.toInt256(),
      fromAcc: order.takerAccount,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });

    // TODO: events!!!!

    // Execute all trades, no need to resubmit manager data
    subAccounts.submitTransfers(transferBatch, "");

    // Return SubAccounts
    _returnAccounts(actions, newAccIds);

    return (newAccIds, newAccOwners);
  }

  /**
   * @dev Send data to IDataReceiver contracts. Can be used to update oracles before pairing trades
   */
  function _processManagerData(bytes memory managerData) internal {
    if (managerData.length == 0) return;
    IBaseManager.ManagerData[] memory managerDatas = abi.decode(managerData, (IBaseManager.ManagerData[]));
    for (uint i; i < managerDatas.length; i++) {
      IDataReceiver(managerDatas[i].receiver).acceptData(managerDatas[i].data);
    }
  }

  function _isPerp(address baseAsset) internal view returns (bool) {
    return isPerpAsset[IPerpAsset(baseAsset)];
  }

  /**
   * @dev Get the difference between the perp price and the traded price
   *      If perp price is $2000, and the limit order matched is trading at $2005, the delta is $5
   *      The bidder (long) needs to pay $5 per Perp contract traded
   */
  function _getPerpDelta(address perpAsset, int marketPrice) internal view returns (int delta) {
    (uint perpPrice,) = IPerpAsset(perpAsset).getPerpPrice();
    return (marketPrice - perpPrice.toInt256());
  }
}
