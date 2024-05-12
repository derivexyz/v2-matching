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
    uint depositExpiry;
    uint minDepositValue;
    uint withdrawalDelay;
    uint depositScale;
    uint withdrawScale;
  }

  struct WithdrawalRequest {
    address beneficiary;
    uint amountShares;
    uint timestamp;
  }

  struct DepositRequest {
    address recipient;
    uint amountDepositAsset;
    uint timestamp;
    uint sharesReceived;
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

  /// @dev Keepers that are are allowed to process deposits and withdrawals
  mapping(address => bool) public shareKeepers;

  mapping(uint => DepositRequest) public queuedDeposit;
  uint public nextQueuedDepositId;
  uint public totalPendingDeposits;

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

  function setShareKeeper(address keeper, bool isKeeper) external onlyOwner {
    shareKeepers[keeper] = isKeeper;
  }

  //////////////
  // Deposits //
  //////////////
  // Deposits are queued and processed in a future block by a trusted keeper. This is to prevent oracle front-running.
  //
  // Each individual deposit is allocated an id, which can be used to track the deposit request. They do not need to be
  // processed sequentially.
  //
  // Deposits can be reverted if they are not processed within a certain time frame.

  function initiateDeposit(uint amount, address recipient) external returns (uint depositId) {
    require(amount >= params.minDepositValue, "deposit below minimum");

    // Then transfer in assets once shares are minted
    depositAsset.transferFrom(msg.sender, address(this), amount);
    totalPendingDeposits += amount;

    // check if deposit cap is exceeded
    require(_getAccountValue() <= int(params.depositCap), "deposit cap exceeded");

    depositId = nextQueuedDepositId++;

    queuedDeposit[depositId] = DepositRequest({
      recipient: recipient,
      amountDepositAsset: amount,
      timestamp: block.timestamp,
      sharesReceived: 0
    });
  }

  function processDeposit(uint depositId) external onlyShareKeeper {
    _processDeposit(depositId);
  }

  function processDeposits(uint[] memory depositIds) external onlyShareKeeper {
    for (uint i = 0; i < depositIds.length; ++i) {
      _processDeposit(depositIds[i]);
    }
  }

  function _processDeposit(uint depositId) internal {
    DepositRequest storage request = queuedDeposit[depositId];

    uint shares = _getSharesForDeposit(request.amountDepositAsset);
    _mint(request.recipient, shares);
    totalPendingDeposits -= request.amountDepositAsset;
    request.sharesReceived = shares;
  }

  function revertPendingDeposit(uint depositId) external {
    DepositRequest storage request = queuedDeposit[depositId];

    if (request.sharesReceived > 0) {
      revert ("Deposit already processed");
    }

    require(block.timestamp > request.timestamp + params.depositExpiry, "Deposit not expired");

    totalPendingDeposits -= request.amountDepositAsset;
    depositAsset.transfer(request.recipient, request.amountDepositAsset);
  }

  // @dev Conversion factor for deposit asset to shares
  function _scaleDeposit(uint amountAsset) internal view virtual returns (uint) {
    return amountAsset * params.depositScale / 1e18;
  }

  /////////////////
  // Withdrawals //
  /////////////////
  // Withdrawals are queued and processed at a future time by a public function. Funds will usually need to be
  // transferred out of the subaccount that is doing the trading, so there is a delay to allow any actions that are
  // required to take place (closing positions, withdrawing to this address, etc).

  function _getSharesForDeposit(uint depositAmount) internal view returns (uint) {
    uint depositAmount18 = ConvertDecimals.to18Decimals(_scaleDeposit(depositAmount), depositAsset.decimals());
    // scale depositAmount by factor and convert to shares
    return _getNumShares(depositAmount18);
  }

  function requestWithdrawal(uint amount) external {
    require(balanceOf(msg.sender) >= amount, "insufficient balance");
    require(amount > 0, "invalid amount");

    _burn(msg.sender, amount);

    queuedWithdrawals[nextQueuedWithdrawalId++] =
      WithdrawalRequest({beneficiary: msg.sender, amountShares: amount, timestamp: block.timestamp});

    totalPendingWithdrawals += amount;
  }

  function processWithdrawalRequests(uint limit) external {
    for (uint i = 0; i < limit; ++i) {
      WithdrawalRequest storage request = queuedWithdrawals[queuedWithdrawalHead];

      if (!shareKeepers[msg.sender] && request.timestamp + params.withdrawalDelay > block.timestamp) {
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
    uint requiredAmount18 = _getSharesValue(_scaleWithdraw(amountShares));
    return ConvertDecimals.from18Decimals(requiredAmount18, depositAsset.decimals());
  }

  function _scaleWithdraw(uint amountShares) internal view virtual returns (uint) {
    return amountShares * params.withdrawScale / 1e18;
  }

  /////////////////////////////
  // Account and share value //
  /////////////////////////////

  /// @dev Function to calculate the value of the account. Must account for pending deposits.
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

  function totalSupply() public view override returns (uint) {
    return ERC20.totalSupply() + totalPendingWithdrawals;
  }

  /////////////////////
  // Trade Execution //
  /////////////////////

  function _isBlocked() internal view returns (bool) {
    return auction.isAuctionLive(subAccount) || auction.getIsWithdrawBlocked();
  }

  modifier onlyShareKeeper() {
    require(shareKeepers[msg.sender], "only share handler");
    _;
  }

  modifier preTransfer() {
    require(!_isBlocked(), "action blocked");
    // TODO: should we settle perps/options? Shouldn't affect MTM
    _;
  }
}
