// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";

/// @title Base Tokenized SubAccount
/// @notice Base class for tokenized subaccounts
/// @dev This contract is abstract and must be inherited by a concrete implementation. It works assuming share decimals
/// are the same as depositAsset decimals.
/// @author Lyra
abstract contract BaseTSA is ERC20, Ownable2Step {
  struct BaseTSAInitParams {
    ISubAccounts subAccounts;
    DutchAuction auction;
    CashAsset cash;
    IWrappedERC20Asset wrappedDepositAsset;
    ILiquidatableManager manager;
    IMatching matching;
    string symbol;
    string name;
  }

  struct TSAParams {
    uint depositCap;
    uint depositExpiry;
    uint minDepositValue;
    uint withdrawalDelay;
    uint depositScale;
    uint withdrawScale;
    uint managementFee;
    address feeRecipient;
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

  ISubAccounts public subAccounts;
  DutchAuction public auction;
  IWrappedERC20Asset public wrappedDepositAsset;
  CashAsset public cash;
  IERC20Metadata public depositAsset;
  ILiquidatableManager public manager;
  IMatching public matching;

  uint public subAccount;

  TSAParams public tsaParams;

  /// @dev Keepers that are are allowed to process deposits and withdrawals
  mapping(address => bool) public shareKeepers;

  mapping(uint => DepositRequest) public queuedDeposit;
  uint public nextQueuedDepositId;
  /// @dev Total amount of pending deposits in depositAsset decimals
  uint public totalPendingDeposits;

  mapping(uint => WithdrawalRequest) public queuedWithdrawals;
  uint public nextQueuedWithdrawalId;
  uint public queuedWithdrawalHead;
  uint public totalPendingWithdrawals;

  /// @dev Last time the fee was collected
  uint public lastFeeCollected;

  constructor(BaseTSAInitParams memory initParams) ERC20(initParams.name, initParams.symbol) Ownable2Step() {
    subAccounts = initParams.subAccounts;
    auction = initParams.auction;
    wrappedDepositAsset = initParams.wrappedDepositAsset;
    cash = initParams.cash;
    manager = initParams.manager;
    depositAsset = wrappedDepositAsset.wrappedAsset();
    matching = initParams.matching;

    subAccount = subAccounts.createAccountWithApproval(address(this), address(matching), initParams.manager);
    matching.depositSubAccount(subAccount);
  }

  ///////////
  // Admin //
  ///////////

  function setTSAParams(TSAParams memory _params) external onlyOwner {
    _collectFee();
    tsaParams = _params;
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

  function initiateDeposit(uint amount, address recipient) external checkBlocked returns (uint depositId) {
    require(amount >= tsaParams.minDepositValue, "deposit below minimum");

    // Then transfer in assets once shares are minted
    depositAsset.transferFrom(msg.sender, address(this), amount);
    totalPendingDeposits += amount;

    // check if deposit cap is exceeded
    require(_getAccountValue() <= tsaParams.depositCap, "deposit cap exceeded");

    depositId = nextQueuedDepositId++;

    queuedDeposit[depositId] =
      DepositRequest({recipient: recipient, amountDepositAsset: amount, timestamp: block.timestamp, sharesReceived: 0});
  }

  function processDeposit(uint depositId) external onlyShareKeeper checkBlocked {
    _collectFee();
    _processDeposit(depositId);
  }

  function processDeposits(uint[] memory depositIds) external onlyShareKeeper checkBlocked {
    _collectFee();
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
      revert("Deposit already processed");
    }

    require(block.timestamp > request.timestamp + tsaParams.depositExpiry, "Deposit not expired");

    totalPendingDeposits -= request.amountDepositAsset;
    depositAsset.transfer(request.recipient, request.amountDepositAsset);
  }

  /// @dev Share decimals are in depositAsset decimals
  function _getSharesForDeposit(uint depositAmount) internal view returns (uint) {
    uint depositAmount18 = _scaleDeposit(depositAmount);
    // scale depositAmount by factor and convert to shares
    return _getNumShares(depositAmount18);
  }

  /// @dev Conversion factor for deposit asset to shares
  function _scaleDeposit(uint amountAsset) internal view virtual returns (uint) {
    return amountAsset * tsaParams.depositScale / 1e18;
  }

  /////////////////
  // Withdrawals //
  /////////////////
  // Withdrawals are queued and processed at a future time by a public function. Funds will usually need to be
  // transferred out of the subaccount that is doing the trading, so there is a delay to allow any actions that are
  // required to take place (closing positions, withdrawing to this address, etc).

  /// @notice Request a withdrawal of an amount of shares. These will be removed from the account and be processed
  /// in the future.
  function requestWithdrawal(uint amount) external checkBlocked {
    require(balanceOf(msg.sender) >= amount, "insufficient balance");
    require(amount > 0, "invalid amount");

    _burn(msg.sender, amount);

    queuedWithdrawals[nextQueuedWithdrawalId++] =
      WithdrawalRequest({beneficiary: msg.sender, amountShares: amount, timestamp: block.timestamp});

    totalPendingWithdrawals += amount;
  }

  /// @notice Process a number of withdrawal requests, up to a limit.
  function processWithdrawalRequests(uint limit) external checkBlocked {
    _collectFee();

    for (uint i = 0; i < limit; ++i) {
      WithdrawalRequest storage request = queuedWithdrawals[queuedWithdrawalHead];

      if (!shareKeepers[msg.sender] && request.timestamp + tsaParams.withdrawalDelay > block.timestamp) {
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
    return amountShares * tsaParams.withdrawScale / 1e18;
  }

  //////////
  // Fees //
  //////////
  function collectFee() external {
    _collectFee();
  }

  /// @dev Must be called before totalSupply is modified to keep amount charged fair
  function _collectFee() internal {
    if (lastFeeCollected == block.timestamp) {
      return;
    }

    if (tsaParams.managementFee == 0 || tsaParams.feeRecipient == address(0)) {
      lastFeeCollected = block.timestamp;
      return;
    }

    uint totalShares = this.totalSupply() + totalPendingWithdrawals;
    if (totalShares == 0) {
      lastFeeCollected = block.timestamp;
      return;
    }

    uint timeSinceLastCollect = block.timestamp - lastFeeCollected;

    uint percentToCollect = timeSinceLastCollect * tsaParams.managementFee / 365 days;
    _mint(tsaParams.feeRecipient, totalShares * percentToCollect / 1e18);
  }

  /////////////////////////////
  // Account and share value //
  /////////////////////////////

  /// @dev Function to calculate the value of the account. Must account for pending deposits.
  /// This is the total amount of "depositAsset" the whole account is worth, **in depositAsset decimals**.
  function _getAccountValue() internal view virtual returns (uint);

  // @dev The amount of "depositAsset" one share is worth, **in 18 decimals**.
  function _getSharePrice() internal view returns (uint) {
    // TODO: avoid the small balance mint/burn share price manipulation at start of vault life
    // totalSupply and accountValue are in depositAsset decimals. Result will be in 18 decimals.
    return totalSupply() == 0 ? 1e18 : _getAccountValue() * 1e18 / totalSupply();
  }

  /// @dev The number of shares that would be minted for an amount of "depositAsset". **In depositAsset decimals**.
  function _getNumShares(uint depositAmount) internal view returns (uint) {
    return depositAmount * _getSharePrice() / 1e18;
  }

  /// @dev The value a given amount of shares in terms of "depositAsset". **In depositAsset decimals**.
  function _getSharesValue(uint numShares) internal view returns (uint) {
    return numShares * _getSharePrice() / 1e18;
  }

  /// @dev The total supply of the token, including pending withdrawals. **In depositAsset decimals**.
  function totalSupply() public view override returns (uint) {
    return ERC20.totalSupply() + totalPendingWithdrawals;
  }

  /////////////////////
  // Trade Execution //
  /////////////////////

  function _isBlocked() internal view returns (bool) {
    return auction.isAuctionLive(subAccount) || auction.getIsWithdrawBlocked() || cash.temporaryWithdrawFeeEnabled();
  }

  modifier onlyShareKeeper() {
    require(shareKeepers[msg.sender], "only share handler");
    _;
  }

  modifier checkBlocked() {
    require(!_isBlocked(), "action blocked");
    _;
  }
}
