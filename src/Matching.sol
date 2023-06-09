// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "v2-core/src/SubAccounts.sol";

import "./interfaces/IMatcher.sol";
import "./SubAccountsManager.sol";
import "./OrderVerifier.sol";

contract Matching is SubAccountsManager, OrderVerifier {
  ///@dev Permissioned address to execute trades
  address tradeExecutor;

  constructor(address _tradeExecutor) EIP712("Matching", "1.0") {
    tradeExecutor = _tradeExecutor;
  }

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice Set which address can submit trades.
   */
  function setTradeExecutor(address newExecutor) external onlyOwner {
    tradeExecutor = newExecutor;

    emit TradeExecutorSet(newExecutor);
  }

  /////////////////////////////
  //  Whitelisted Functions  //
  /////////////////////////////

  function verifyAndMatch(SignedOrder[] memory orders, bytes memory matchData) public onlyTradeExecutor {
    IMatcher matcher = orders[0].matcher;
    IMatcher.VerifiedOrder[] memory verifiedOrders = new IMatcher.VerifiedOrder[](orders.length);
    for (uint i = 0; i < orders.length; i++) {
      verifiedOrders[i] = _verifyOrder(orders[i], matcher);
    }
    _submitMatch(matcher, verifiedOrders, matchData);
  }

  // function updateAccountOwners(uint[] memory accountIds, uint[] memory owners) {
  //   if (accountIds.length != owners.length) revert M_ArrayLengthMismatch(accountIds.length, owners.length);
  //   for (uint i = 0; accountIds.length; ++i) {
  //     accountToOwner[accountIds[i]] = owners[i];
  //   }
  // }

  //////////////////////////
  //  External Functions  //
  //////////////////////////

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  function _submitMatch(IMatcher matcher, IMatcher.VerifiedOrder[] memory orders, bytes memory matchData) internal {
    // Transfer accounts to Matcher contract
    for (uint i = 0; orders.legnth;) {
      accounts.transferFrom(address(this), address(matcher), orders[i].accountId);
      unchecked {
        i++;
      }
    }

    (uint[] memory accountIds, uint[] memory owners) = matcher.matchOrders(orders, matchData);

    // Ensure accounts are transferred back
    for (uint i = 0; orders.legnth; ++i) {
      address tokenOwner = accounts.ownerOf(orders[i].accountId);
      if (tokenOwner != address(this)) {
        revert M_NotTokenOwner(orders[i].accountId, tokenOwner);
      }
    }

    // Receive back a list of subaccounts and updated owners? This is more general and allows for opening new accounts
    // in matcher modules // todo what if the module calls updateAccountOwners?
    if (accountIds.length != owners.length) revert M_ArrayLengthMismatch(accountIds.length, owners.length);
    for (uint i = 0; accountIds.length; ++i) {
      accountToOwner[accountIds[i]] = owners[i];
    }
  }

  modifier onlyTradeExecutor() {
    require(msg.sender == tradeExecutor, "Only trade executor can call this");
    _;
  }

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when SubAccounts contract is set.
   */
  event TradeExecutorSet(address newExecutor);
}
