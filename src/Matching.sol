// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import {IMatchingModule} from "./interfaces/IMatchingModule.sol";
import {SubAccountsManager} from "./SubAccountsManager.sol";
import "./OrderVerifier.sol";

contract Matching is OrderVerifier {
  ///@dev Permissioned address to execute trades
  mapping(address tradeExecutor => bool canExecuteTrades) public tradeExecutors;
  // todo whitelist module

  constructor(ISubAccounts _accounts) OrderVerifier(_accounts) {}

  error M_AccountNotReturned();

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
      verifiedOrders[i] = _verifyOrder(orders[i]);
    }
    _submitMatch(matcher, verifiedOrders, matchData);
  }

  //////////////////////////
  //  External Functions  //
  //////////////////////////

  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  function _submitMatch(IMatchingModule matcher, IMatchingModule.VerifiedOrder[] memory orders, bytes memory matchData)
    internal
  {
    // Transfer accounts to Matcher contract
    for (uint i = 0; i < orders.length; ++i) {
      // Allow signing messages with accountId == 0, where no account needs to be transferred.
      if (orders[i].accountId == 0) continue;

      accounts.transferFrom(address(this), address(matcher), orders[i].accountId);
    }

    (uint[] memory newAccIds, address[] memory newOwners) = matcher.matchOrders(orders, matchData);

    // Ensure accounts are transferred back,
    for (uint i = 0; i < orders.length; ++i) {
      if (orders[i].accountId != 0 && accounts.ownerOf(orders[i].accountId) != address(this)) {
        revert M_AccountNotReturned();
      }
    }

    // Receive back a list of new subaccounts and respective owners. This allows modules to open new accounts
    if (newAccIds.length != newOwners.length) revert M_ArrayLengthMismatch(newAccIds.length, newOwners.length);
    for (uint i = 0; i < newAccIds.length; ++i) {
      if (accounts.ownerOf(newAccIds[i]) != address(this)) revert M_AccountNotReturned();
      if (accountToOwner[newAccIds[i]] != address(0)) revert("account already exists");

      accountToOwner[newAccIds[i]] = newOwners[i];
    }
  }

  function getOrderHash(SignedOrder memory order) external pure returns (bytes32) {
    return _getOrderHash(order);
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

  error M_ArrayLengthMismatch(uint length1, uint length2);
}
