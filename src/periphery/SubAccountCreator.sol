// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";

import "../interfaces/IMatching.sol";

/**
 * @title SubAccountCreator
 */
contract SubAccountCreator {
  ISubAccounts public immutable subAccounts;

  ICashAsset public immutable cash;

  IMatching public immutable matching;

  IERC20 public immutable usdc;

  constructor(ISubAccounts _subAccounts, ICashAsset _cash, IMatching _matching) {
    subAccounts = _subAccounts;
    cash = _cash;
    matching = _matching;

    usdc = _cash.wrappedAsset();
    usdc.approve(address(_cash), type(uint).max);

    _subAccounts.setApprovalForAll(address(_matching), true);
  }

  /**
   * @notice Helper function to help user deposit USDC + enable trading in a single transaction
   * @param initUSDCDeposit Initial deposit that will be pulled from user to the account
   * @param manager The manager address for the new account
   */
  function createAndDepositSubAccount(uint initUSDCDeposit, IManager manager) external returns (uint accountId) {
    if (initUSDCDeposit > 0) {
      usdc.transferFrom(msg.sender, address(this), initUSDCDeposit);

      // add USDC to new SubAccount
      accountId = cash.depositToNewAccount(address(this), initUSDCDeposit, manager);
    } else {
      // create a
      accountId = subAccounts.createAccount(address(this), manager);
    }

    matching.depositSubAccountFor(accountId, msg.sender);
  }
}
