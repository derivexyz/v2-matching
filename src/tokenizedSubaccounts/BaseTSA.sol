// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {StandardManager} from "v2-core/src/risk-managers/StandardManager.sol";
import {PMRM, IPMRM} from "v2-core/src/risk-managers/PMRM.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseModule} from "../modules/BaseModule.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

// TODO: handle valuation when there is an insolvency
abstract contract BaseTSA is ERC20, Ownable2Step {
  struct Params {
    uint depositCap;
    uint minDepositValue;
    uint withdrawalDelay;
  }

  struct WithdrawalRequest {
    address beneficiary;
    uint amountShares;
    uint timestamp;
  }

  struct BaseTSAInitParams {
    ISubAccounts subAccounts;
    DutchAuction auction;
    IWrappedERC20Asset wrappedDepositAsset;
    ILiquidatableManager manager;
    IMatching matching;
    string symbol;
    string name;
  }

  ISubAccounts public subAccounts;
  DutchAuction public auction;
  IWrappedERC20Asset public wrappedDepositAsset;
  IERC20Metadata public depositAsset;
  ILiquidatableManager public manager;
  IMatching public matching;

  uint public subAccount;

  Params public params;

  mapping(uint => WithdrawalRequest) public queuedWithdrawals;
  uint public nextQueuedWithdrawalId;
  uint public queuedWithdrawalHead;
  uint public totalPendingWithdrawals;

  constructor(BaseTSAInitParams memory initParams) ERC20(initParams.name, initParams.symbol) Ownable2Step() {
    subAccounts = initParams.subAccounts;
    auction = initParams.auction;
    wrappedDepositAsset = initParams.wrappedDepositAsset;
    manager = initParams.manager;
    depositAsset = wrappedDepositAsset.wrappedAsset();
    matching = initParams.matching;

    subAccount = subAccounts.createAccountWithApproval(address(this), address(matching), initParams.manager);
    matching.depositSubAccount(subAccount);
  }

  ///////////
  // Admin //
  ///////////

  function setParams(Params memory _params) external onlyOwner {
    params = _params;
  }

  function addSessionKey(address sessionKey, uint expiry) external onlyOwner {
    matching.registerSessionKey(sessionKey, expiry);
  }

  function removeSessionKey(address sessionKey) external onlyOwner {
    matching.deregisterSessionKey(sessionKey);
  }

  function approveModule(address module) external onlyOwner {
    require(matching.allowedModules(module), "module not approved");

    depositAsset.approve(module, type(uint).max);
  }

  //////////////////////////
  // Deposit and Withdraw //
  //////////////////////////
  function deposit(uint depositAmount) external preTransfer {
    // TODO: reentrancy guard
    // Work out value of pool excluding the new funds to work out number of shares
    _mint(msg.sender, _getSharesForDeposit(depositAmount));
    // Then transfer in assets once shares are minted
    depositAsset.transferFrom(msg.sender, address(this), depositAmount);

    // check if deposit cap is exceeded
    require(_getAccountValue() <= int(params.depositCap), "deposit cap exceeded");
  }

  function _getSharesForDeposit(uint depositAmount) internal view returns (uint) {
    uint depositAmount18 = ConvertDecimals.to18Decimals(depositAmount, depositAsset.decimals());
    // scale depositAmount by factor and convert to shares
    uint scaledDeposit18 = _getDepositWithdrawFactor() * depositAmount18 / 1e18;
    return _getNumShares(scaledDeposit18);
  }

  function requestWithdrawal(uint amount) external {
    require(balanceOf(msg.sender) >= amount, "insufficient balance");
    require(amount > 0, "invalid amount");

    _burn(msg.sender, amount);

    queuedWithdrawals[nextQueuedWithdrawalId++] =
      WithdrawalRequest({beneficiary: msg.sender, amountShares: amount, timestamp: block.timestamp});

    totalPendingWithdrawals += amount;
  }

  function processWithdrawalRequests(uint limit) external onlyOwner {
    for (uint i = 0; i < limit; ++i) {
      WithdrawalRequest storage request = queuedWithdrawals[queuedWithdrawalHead];

      if (request.timestamp + params.withdrawalDelay > block.timestamp) {
        break;
      }

      uint totalBalance = depositAsset.balanceOf(address(this));
      uint requiredAmount = _getSharesToWithdrawAmount(request.amountShares);

      if (totalBalance < requiredAmount) {
        // withdraw a portion
        uint withdrawAmount = totalBalance;
        depositAsset.transfer(request.beneficiary, withdrawAmount);
        uint difference = requiredAmount - withdrawAmount;
        uint finalShareAmount = request.amountShares * difference / requiredAmount;
        totalPendingWithdrawals -= (request.amountShares - finalShareAmount);
        request.amountShares = finalShareAmount;
        break;
      } else {
        depositAsset.transfer(request.beneficiary, requiredAmount);
        totalPendingWithdrawals -= request.amountShares;
        request.amountShares = 0;
      }
      queuedWithdrawalHead++;
    }
  }

  function _getSharesToWithdrawAmount(uint amountShares) internal view returns (uint amountDepositAsset) {
    uint requiredAmount18 = _getSharesValue(amountShares);
    uint requiredAmount = ConvertDecimals.from18Decimals(requiredAmount18, depositAsset.decimals());
    // scale amount by factor
    return requiredAmount * 1e18 / _getDepositWithdrawFactor();
  }

  /////////////////////////////
  // Account and share value //
  /////////////////////////////

  function _getAccountValue() internal view virtual returns (int);

  function _getSharePrice() internal view returns (int) {
    // TODO: avoid the small balance mint/burn share price manipulation
    int totalSupplyInt = int(totalSupply());
    return totalSupplyInt == 0 ? int(1e18) : _getAccountValue() * 1e18 / totalSupplyInt;
  }

  function _getNumShares(uint depositAmount) internal view returns (uint) {
    int depositAmountInt = int(depositAmount);
    require(depositAmountInt >= 0, "depositAmount overflow");
    return uint(depositAmountInt * _getSharePrice() / 1e18);
  }

  /// @dev in 18dp
  function _getSharesValue(uint numShares) internal view returns (uint) {
    int numSharesInt = int(numShares);
    require(numSharesInt >= 0, "numShares overflow");
    return uint(numSharesInt * _getSharePrice() / 1e18);
  }

  function _getDepositWithdrawFactor() internal view virtual returns (uint) {
    return 1e18;
  }

  function totalSupply() public view override returns (uint) {
    return ERC20.totalSupply() + totalPendingWithdrawals;
  }

  /////////////////////
  // Trade Execution //
  /////////////////////

  function _isBlocked() internal view returns (bool) {
    return auction.isAuctionLive(subAccount) || auction.getIsWithdrawBlocked();
  }

  modifier preTransfer() {
    require(!_isBlocked(), "action blocked");
    // TODO: should we settle perps/options? Shouldn't affect MTM
    _;
  }
}
