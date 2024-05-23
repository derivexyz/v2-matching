// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "./BaseOnChainSigningTSA.sol";
import {IOptionAsset} from "v2-core/src/interfaces/IOptionAsset.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IDepositModule} from "../interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";
import "lyra-utils/math/IntLib.sol";

/// @title LRTCCTSA
/// @notice TSA that accepts LRTs as deposited collateral, and sells covered calls.
/// @dev Prices shares in USD, but accepts baseAsset as deposit. Vault intended to try remain delta neutral.
contract LRTCCTSA is BaseOnChainSigningTSA {
  using IntLib for int;

  struct LRTCCTSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawModule;
    ITradeModule tradeModule;
    IOptionAsset optionAsset;
  }

  ISpotFeed public baseFeed;
  IDepositModule public depositModule;
  IWithdrawalModule public withdrawModule;
  ITradeModule public tradeModule;
  IOptionAsset public optionAsset;
  bytes32 public lastSeenHash;

  constructor(BaseTSA.BaseTSAInitParams memory initParams, LRTCCTSAInitParams memory lrtCcParams)
    BaseOnChainSigningTSA(initParams)
  {
    baseFeed = lrtCcParams.baseFeed;
    depositModule = lrtCcParams.depositModule;
    withdrawModule = lrtCcParams.withdrawModule;
    tradeModule = lrtCcParams.tradeModule;
    optionAsset = lrtCcParams.optionAsset;
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash) internal virtual override {
    // Disable last seen hash when a new one comes in.
    // We dont want to have to track pending withdrawals etc. in the logic, and work out if when they've been executed
    signedData[lastSeenHash] = false;
    lastSeenHash = actionHash;

    if (address(action.module) == address(depositModule)) {
      _verifyDepositAction(action);
    } else if (address(action.module) == address(withdrawModule)) {
      _verifyWithdrawAction(action);
    } else if (address(action.module) == address(tradeModule)) {
      _verifyTradeAction(action);
    } else {
      revert("LRTCCTSA: Invalid module");
    }
  }

  //////////////
  // Deposits //
  //////////////

  function _verifyDepositAction(IMatching.Action memory action) internal view {
    IDepositModule.DepositData memory depositData = abi.decode(action.data, (IDepositModule.DepositData));
    if (depositData.asset != address(wrappedDepositAsset)) {
      revert("LRTCCTSA: Invalid asset");
    }
  }

  /////////////////
  // Withdrawals //
  /////////////////

  function _verifyWithdrawAction(IMatching.Action memory action) internal view {
    IWithdrawalModule.WithdrawalData memory withdrawalData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));
    if (withdrawalData.asset != address(wrappedDepositAsset)) {
      revert("LRTCCTSA: Invalid asset");
    }

    (uint numShortCalls, uint baseBalance) = _getAccountStats();
    if (numShortCalls > baseBalance + withdrawalData.assetAmount) {
      revert("LRTCCTSA: Cannot withdraw utilised collateral");
    }
  }

  /////////////
  // Trading //
  /////////////

  function _verifyTradeAction(IMatching.Action memory action) internal view {
    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));
    if (tradeData.asset == address(wrappedDepositAsset)) {
      // Always allow depositing the baseAsset
      return;
    } else if (tradeData.asset == address(optionAsset)) {
      // TODO: verify
      // - delta of option is above threshold
      // - limit price is within acceptable bounds
      // - amount of options wont exceed base balance
    } else {
      revert("LRTCCTSA: Invalid asset");
    }
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getAccountValue() internal view override returns (int) {
    // TODO: double check perp Pnl, funding, cash interest
    uint depositAssetBalance = depositAsset.balanceOf(address(this));

    (, int mtm) = manager.getMarginAndMarkToMarket(subAccount, true, 0);
    (uint spotPrice,) = baseFeed.getSpot();

    return int(depositAssetBalance) + mtm * 1e18 / int(spotPrice) - int(totalPendingDeposits);
  }

  function _getAccountStats() internal view returns (uint numShortCalls, uint baseBalance) {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(subAccount);
    for (uint i = 0; i < balances.length; i++) {
      if (balances[i].asset == optionAsset) {
        int balance = balances[i].balance;
        if (balance > 0) {
          revert("LRTCCTSA: Invalid option balance");
        }
        numShortCalls += balances[i].balance.abs();
      } else if (balances[i].asset == wrappedDepositAsset) {
        baseBalance = balances[i].balance.abs();
      }
    }
    return (numShortCalls, baseBalance);
  }
}
