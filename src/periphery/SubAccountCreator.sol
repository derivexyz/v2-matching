// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {ICashAsset} from "v2-core/src/interfaces/ICashAsset.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";

import "../interfaces/IMatching.sol";

/**
 * @title SubAccountCreator
 */
contract SubAccountCreator {
  ISubAccounts public immutable subAccounts;

  IMatching public immutable matching;

  constructor(ISubAccounts _subAccounts, IMatching _matching) {
    subAccounts = _subAccounts;

    matching = _matching;

    _subAccounts.setApprovalForAll(address(_matching), true);
  }

  /**
   * @notice Helper function to help user deposit USDC + enable trading in a single transaction
   * @param initDeposit Initial deposit that will be pulled from msg.sender to open the subaccount with
   * @param manager The manager address for the new account
   */
  function createAndDepositSubAccount(IERC20BasedAsset baseAsset, uint initDeposit, IManager manager)
    external
    returns (uint accountId)
  {
    accountId = subAccounts.createAccount(address(this), manager);

    if (initDeposit > 0) {
      IERC20 erc20 = baseAsset.wrappedAsset();

      erc20.transferFrom(msg.sender, address(this), initDeposit);

      erc20.approve(address(baseAsset), type(uint).max);

      baseAsset.deposit(accountId, initDeposit);
    }

    // enable trading: deposit subaccount into Matching
    matching.depositSubAccountFor(accountId, msg.sender);
  }
}
