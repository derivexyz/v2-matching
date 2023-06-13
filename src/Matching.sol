// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "v2-core/interfaces/ISubAccounts.sol";

import "./interfaces/IMatchingModule.sol";
import "./SubAccountsManager.sol";
import "./OrderVerifier.sol";

contract Matching is OrderVerifier {
  ///@dev Permissioned address to execute trades
  mapping(address tradeExecutor => bool canExecuteTrades) public tradeExecutors;

  constructor(ISubAccounts _accounts) OrderVerifier(_accounts) {}

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice Set which address can submit trades.
   */
  function setTradeExecutor(address tradeExecutor, bool canExecute) external onlyOwner {
    tradeExecutors[tradeExecutor] = canExecute;

    emit TradeExecutorSet(tradeExecutor, canExecute);
  }

  /////////////////////////////
  //  Whitelisted Functions  //
  /////////////////////////////

  function verifyAndMatch(SignedOrder[] memory orders, bytes memory matchData) public onlyTradeExecutor {
    IMatchingModule matcher = orders[0].matcher;
    IMatchingModule.VerifiedOrder[] memory verifiedOrders = new IMatchingModule.VerifiedOrder[](orders.length);
    for (uint i = 0; i < orders.length; i++) {
      verifiedOrders[i] = _verifyOrder(orders[i], matcher);
    }
    _submitMatch(matcher, verifiedOrders, matchData);
  }

  //////////////////////////
  //  External Functions  //
  //////////////////////////

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  function _submitMatch(IMatchingModule matcher, IMatchingModule.VerifiedOrder[] memory orders, bytes memory matchData) internal {
    // Transfer accounts to Matcher contract
    for (uint i = 0; i < orders.length; ++i) {
      // Allow signing messages with accountId == 0, where no account needs to be transferred.
      if (orders[i].accountId == 0) continue;

      accounts.transferFrom(address(this), address(matcher), orders[i].accountId);
    }

    (uint[] memory newAccIds, address[] memory newOwners) = matcher.matchOrders(orders, matchData);

    // Ensure accounts are transferred back,
    for (uint i = 0; i < orders.length; ++i) {
      if (accounts.ownerOf(orders[i].accountId) != address(this)) revert("token not returned");
    }

    // Receive back a list of new subaccounts and respective owners. This allows modules to open new accounts
    if (newAccIds.length != newOwners.length) revert M_ArrayLengthMismatch(newAccIds.length, newOwners.length);
    for (uint i = 0; i < newAccIds.length; ++i) {
      if (accounts.ownerOf(newAccIds[i]) != address(this)) revert("new account not returned");
      if (accountToOwner[newAccIds[i]] != address(0)) revert("account already exists");

      accountToOwner[newAccIds[i]] = newOwners[i];
    }
  }

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyTradeExecutor() {
    require(tradeExecutors[msg.sender], "Only trade executor can call this");
    _;
  }

  ////////////
  // Events //
  ////////////

  event TradeExecutorSet(address executor, bool canExecute);
}
