// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title Base Tokenized SubAccount
/// @notice Base class for tokenized subaccounts
/// @dev This contract is abstract and must be inherited by a concrete implementation. It works assuming share decimals
/// are the same as depositAsset decimals.
/// @author Lyra
abstract contract BaseTSA is ERC20Upgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
  struct BaseTSAInitParams {
    ISubAccounts subAccounts;
    DutchAuction auction;
    CashAsset cash;
    IWrappedERC20Asset wrappedDepositAsset;
    ILiquidatableManager manager;
    IMatching matching;
    string symbol;
    string name;
    TSAParams initialParams;
  }

  struct BaseTSAAddresses {
    ISubAccounts subAccounts;
    DutchAuction auction;
    IWrappedERC20Asset wrappedDepositAsset;
    CashAsset cash;
    IERC20Metadata depositAsset;
    ILiquidatableManager manager;
    IMatching matching;
  }

  struct TSAParams {
    /// @dev total amount of "depositAsset" the whole account can be worth, **in depositAsset decimals**.
    uint depositCap;
    /// @dev minimum deposit amount of "depositAsset", in depositAsset decimals
    uint minDepositValue;
    /// @dev multipliers for deposit amounts, to allow for conversions like 1:3000, as well as charging a deposit fee
    uint depositScale;
    /// @dev multipliers for withdrawal amounts, to allow for conversions like 3000:1, as well as charging a fee
    uint withdrawScale;
    uint managementFee;
    address feeRecipient;
    // Performance fee
    uint performanceFee;
    uint performanceFeeWindow;
  }

  /// @dev A withdrawal is considered complete when amountShares is 0. They can be partially completed.
  struct WithdrawalRequest {
    address beneficiary;
    uint amountShares;
    uint timestamp;
    uint assetsReceived;
  }

  /// @dev A deposit is considered complete when sharesReceived is > 0. There are no partially complete deposits.
  struct DepositRequest {
    address recipient;
    uint amountDepositAsset;
    uint timestamp;
    uint sharesReceived;
  }

  /// @custom:storage-location erc7201:lyra.storage.BaseTSA
  struct BaseTSAStorage {
    ISubAccounts subAccounts;
    DutchAuction auction;
    IWrappedERC20Asset wrappedDepositAsset;
    CashAsset cash;
    IERC20Metadata depositAsset;
    ILiquidatableManager manager;
    IMatching matching;
    uint subAccount;
    TSAParams tsaParams;
    /// @dev Keepers that are are allowed to process deposits and withdrawals
    mapping(address => bool) shareKeepers;
    mapping(uint => DepositRequest) queuedDeposit;
    uint nextQueuedDepositId;
    mapping(uint => WithdrawalRequest) queuedWithdrawals;
    uint nextQueuedWithdrawalId;
    uint queuedWithdrawalHead;
    /// @dev Total amount of pending deposits in depositAsset decimals
    uint totalPendingDeposits;
    uint totalPendingWithdrawals;
    /// @dev Last time the fee was collected
    uint lastFeeCollected;
    // Performance fee
    uint lastPerfSnapshot;
    uint lastPerfSnapshotValue;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.BaseTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant BaseTSAStorageLocation = 0x5dfed237c807655691d61cacf0fafd8d8cac98f5cca2d37d7fc033aa25733b00;

  function _getBaseTSAStorage() private pure returns (BaseTSAStorage storage $) {
    assembly {
      $.slot := BaseTSAStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function __BaseTSA_init(address initialOwner, BaseTSAInitParams memory initParams) internal onlyInitializing {
    // Use "unchained" to make sure an existing owner isn't replaced when upgraded
    __Ownable_init_unchained(initialOwner);
    __ERC20_init(initParams.name, initParams.symbol);
    __ReentrancyGuard_init();

    BaseTSAStorage storage $ = _getBaseTSAStorage();

    $.subAccounts = initParams.subAccounts;
    $.auction = initParams.auction;
    $.wrappedDepositAsset = initParams.wrappedDepositAsset;
    $.cash = initParams.cash;
    $.manager = initParams.manager;
    $.depositAsset = $.wrappedDepositAsset.wrappedAsset();
    $.matching = initParams.matching;

    _setTSAParams(initParams.initialParams);

    if ($.subAccount == 0) {
      $.subAccount = $.subAccounts.createAccountWithApproval(address(this), address($.matching), $.manager);
      $.matching.depositSubAccount($.subAccount);
    }
  }

  function decimals() public view virtual override returns (uint8) {
    return getBaseTSAAddresses().depositAsset.decimals();
  }

  ///////////
  // Admin //
  ///////////

  function setTSAParams(TSAParams memory _params) external onlyOwner {
    _setTSAParams(_params);
  }

  function _setTSAParams(TSAParams memory _params) internal {
    _collectFee();

    uint scaleRatio = _params.depositScale * 1e18 / _params.withdrawScale;

    require(
      _params.managementFee <= 0.2e18
        && scaleRatio <= 1.12e18
        && scaleRatio >= 0.9e18
        && _params.performanceFee <= 1e18
        && _params.performanceFeeWindow > 0,
      BTSA_InvalidParams()
    );

    _getBaseTSAStorage().tsaParams = _params;

    emit TSAParamsUpdated(_params);
  }

  function approveModule(address module, uint amount) external onlyOwner {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    if (!$.matching.allowedModules(module)) {
      revert BTSA_ModuleNotPartOfMatching();
    }

    $.depositAsset.approve(module, amount);

    emit ModuleApproved(module);
  }

  function setShareKeeper(address keeper, bool isKeeper) external onlyOwner {
    _getBaseTSAStorage().shareKeepers[keeper] = isKeeper;

    emit ShareKeeperUpdated(keeper, isKeeper);
  }

  //////////////
  // Deposits //
  //////////////
  // Deposits are queued and processed in a future block by a trusted keeper. This is to prevent oracle front-running.
  //
  // Each individual deposit is allocated an id, which can be used to track the deposit request. They do not need to be
  // processed sequentially.

  function initiateDeposit(uint amount, address recipient) external checkBlocked nonReentrant returns (uint depositId) {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    if (amount < $.tsaParams.minDepositValue) {
      revert BTSA_DepositBelowMinimum();
    }
    // Then transfer in assets once shares are minted
    $.depositAsset.transferFrom(msg.sender, address(this), amount);
    $.totalPendingDeposits += amount;

    // check if deposit cap is exceeded
    if (_getAccountValue(true) > $.tsaParams.depositCap) {
      revert BTSA_DepositCapExceeded();
    }

    depositId = $.nextQueuedDepositId++;

    $.queuedDeposit[depositId] =
      DepositRequest({recipient: recipient, amountDepositAsset: amount, timestamp: block.timestamp, sharesReceived: 0});

    emit DepositInitiated(depositId, recipient, amount);

    return depositId;
  }

  function processDeposit(uint depositId) external onlyShareKeeper checkBlocked {
    _collectFee();
    _processDeposit(depositId);
  }

  /// @notice Process a number of deposit requests.
  function processDeposits(uint[] memory depositIds) external onlyShareKeeper checkBlocked {
    _collectFee();
    for (uint i = 0; i < depositIds.length; ++i) {
      _processDeposit(depositIds[i]);
    }
  }

  function _processDeposit(uint depositId) internal {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    DepositRequest storage request = $.queuedDeposit[depositId];

    if (request.sharesReceived > 0) {
      revert BTSA_DepositAlreadyProcessed();
    }
    uint shares = _getSharesForDeposit(request.amountDepositAsset);

    if (shares == 0) {
      revert BTSA_MustReceiveShares();
    }

    request.sharesReceived = shares;
    $.totalPendingDeposits -= request.amountDepositAsset;

    _mint(request.recipient, shares);

    emit DepositProcessed(depositId, request.recipient, true, shares);
  }

  /// @dev Share decimals are in depositAsset decimals
  function _getSharesForDeposit(uint depositAmount) internal view returns (uint) {
    // scale depositAmount by factor and convert to shares
    return getNumShares(_scaleDeposit(depositAmount));
  }

  /// @dev Conversion factor for deposit asset to shares. Returns in amountAsset decimals
  function _scaleDeposit(uint amountAsset) internal view virtual returns (uint) {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    return amountAsset * $.tsaParams.depositScale / 1e18;
  }

  /////////////////
  // Withdrawals //
  /////////////////
  // Withdrawals are queued and processed at a future time by a public function. Funds will usually need to be
  // transferred out of the subaccount that is doing the trading, so there is a delay to allow any actions that are
  // required to take place (closing positions, withdrawing to this address, etc).

  /// @notice Request a withdrawal of an amount of shares. These will be removed from the account and be processed
  /// in the future.
  function requestWithdrawal(uint amount) external checkBlocked nonReentrant returns (uint withdrawalId) {
    BaseTSAStorage storage $ = _getBaseTSAStorage();
    if (balanceOf(msg.sender) < amount) {
      revert BTSA_InsufficientBalance();
    }
    if (amount == 0) {
      revert BTSA_InvalidWithdrawalAmount();
    }

    withdrawalId = $.nextQueuedWithdrawalId++;

    $.queuedWithdrawals[withdrawalId] =
      WithdrawalRequest({beneficiary: msg.sender, amountShares: amount, timestamp: block.timestamp, assetsReceived: 0});

    $.totalPendingWithdrawals += amount;

    _burn(msg.sender, amount);

    emit WithdrawalRequested(withdrawalId, msg.sender, amount);
  }

  /// @notice Process a number of withdrawal requests, up to a limit.
  function processWithdrawalRequests(uint limit) external checkBlocked onlyShareKeeper nonReentrant {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    _collectFee();

    for (uint i = 0; i < limit; ++i) {
      if ($.queuedWithdrawalHead >= $.nextQueuedWithdrawalId) {
        break;
      }

      WithdrawalRequest storage request = $.queuedWithdrawals[$.queuedWithdrawalHead];

      uint totalBalance = $.depositAsset.balanceOf(address(this)) - $.totalPendingDeposits;

      uint requiredAmount = _getSharesToWithdrawAmount(request.amountShares);

      if (totalBalance == 0) {
        break;
      }

      if (totalBalance < requiredAmount) {
        // withdraw a portion
        uint withdrawAmount = totalBalance;
        uint difference = requiredAmount - withdrawAmount;
        uint finalShareAmount = request.amountShares * difference / requiredAmount;
        uint sharesRedeemed = request.amountShares - finalShareAmount;

        uint finalWithdrawAmount = _collectWithdrawalPerfFee(sharesRedeemed, withdrawAmount);

        $.totalPendingWithdrawals -= sharesRedeemed;
        request.amountShares = finalShareAmount;
        request.assetsReceived += withdrawAmount;

        emit WithdrawalProcessed($.queuedWithdrawalHead, request.beneficiary, false, sharesRedeemed, withdrawAmount);

        $.depositAsset.transfer(request.beneficiary, withdrawAmount);
        break;
      } else {
        uint sharesRedeemed = request.amountShares;

        uint finalWithdrawAmount = _collectWithdrawalPerfFee(sharesRedeemed, requiredAmount);

        $.totalPendingWithdrawals -= sharesRedeemed;
        request.amountShares = 0;
        request.assetsReceived += requiredAmount;

        emit WithdrawalProcessed($.queuedWithdrawalHead, request.beneficiary, true, sharesRedeemed, requiredAmount);

        $.depositAsset.transfer(request.beneficiary, requiredAmount);
      }
      $.queuedWithdrawalHead++;
    }
  }

  function _getSharesToWithdrawAmount(uint amountShares) internal view returns (uint amountDepositAsset) {
    return getSharesValue(_scaleWithdraw(amountShares));
  }

  /// @dev Conversion factor for shares to deposit asset. Returns in amountAsset decimals.
  function _scaleWithdraw(uint amountShares) internal view virtual returns (uint) {
    return amountShares * _getBaseTSAStorage().tsaParams.withdrawScale / 1e18;
  }

  //////////
  // Fees //
  //////////

  /// @notice Public function to trigger fee collection
  function collectFee() external {
    _collectFee();
  }

  /// @dev Must be called before totalSupply is modified to keep amount charged fair
  function _collectFee() internal {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    if ($.lastFeeCollected == block.timestamp) {
      return;
    }

    if (($.tsaParams.managementFee == 0 && $.tsaParams.performanceFee == 0) || $.tsaParams.feeRecipient == address(0)) {
      $.lastFeeCollected = block.timestamp;
      return;
    }

    uint sharePrice = _getSharePrice();

    if ($.lastPerfSnapshot == 0) {
      $.lastPerfSnapshot = block.timestamp;
      $.lastPerfSnapshotValue = sharePrice;
    }

    uint totalShares = this.totalSupply();
    if (totalShares == 0) {
      $.lastFeeCollected = block.timestamp;
      return;
    }

    uint timeSinceLastCollect = block.timestamp - $.lastFeeCollected;
    uint percentToCollect = timeSinceLastCollect * $.tsaParams.managementFee / 365 days;
    uint amountCollected = totalShares * percentToCollect / 1e18;

    if ($.lastPerfSnapshot + $.tsaParams.performanceFeeWindow > block.timestamp) {
      if (sharePrice > $.lastPerfSnapshotValue) {
        uint perfFee = (sharePrice - $.lastPerfSnapshotValue) * $.tsaParams.performanceFee / sharePrice;
        amountCollected += totalShares * perfFee / 1e18;
      }
      $.lastPerfSnapshot = block.timestamp;
      $.lastPerfSnapshotValue = sharePrice;
    }

    _mint($.tsaParams.feeRecipient, amountCollected);

    $.lastFeeCollected = block.timestamp;

    emit FeeCollected($.tsaParams.feeRecipient, amountCollected, block.timestamp, totalShares);
  }

  function _collectWithdrawalPerfFee(uint sharesBurnt, uint withdrawAmount) internal returns (uint finalWithdrawAmount) {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    if (
      $.tsaParams.performanceFee == 0
      || $.tsaParams.feeRecipient == address(0)
      || $.lastPerfSnapshot == block.timestamp
    ) {
      return finalWithdrawAmount;
    }

    if ($.lastPerfSnapshot == 0) {
      $.lastPerfSnapshot = block.timestamp;
      $.lastPerfSnapshotValue = _getSharePrice();
      return finalWithdrawAmount;
    }

    uint sharePrice = _getSharePrice();

    if ($.lastPerfSnapshot + $.tsaParams.performanceFeeWindow > block.timestamp) {
      if (sharePrice > $.lastPerfSnapshotValue) {
        uint perfFee = (sharePrice - $.lastPerfSnapshotValue) * $.tsaParams.performanceFee / sharePrice;
        uint amountCollected = sharesBurnt * perfFee / 1e18;

        _mint($.tsaParams.feeRecipient, amountCollected);

        return withdrawAmount * perfFee / 1e18;
      }
      return finalWithdrawAmount;
    }
  }

  /////////////////////////////
  // Account and share value //
  /////////////////////////////

  /// @dev Function to calculate the value of the account. Must account for pending deposits.
  /// This is the total amount of "depositAsset" the whole account is worth, **in depositAsset decimals**.
  function _getAccountValue(bool includePending) internal view virtual returns (uint);

  // @dev The amount of "depositAsset" one share is worth, **in 18 decimals**.
  function _getSharePrice() internal view returns (uint) {
    // totalSupply and accountValue are in depositAsset decimals. Result will be in 18 decimals.
    return totalSupply() == 0 ? 1e18 : _getAccountValue(false) * 1e18 / totalSupply();
  }

  /// @dev The number of shares that would be minted for an amount of "depositAsset". **In depositAsset decimals**.
  function getNumShares(uint depositAmount) public view returns (uint) {
    return depositAmount * 1e18 / _getSharePrice();
  }

  /// @dev The value a given amount of shares in terms of "depositAsset". **In depositAsset decimals**.
  function getSharesValue(uint numShares) public view returns (uint) {
    return numShares * _getSharePrice() / 1e18;
  }

  /// @dev The total supply of the token, including pending withdrawals. **In depositAsset decimals**.
  function totalSupply() public view override returns (uint) {
    return super.totalSupply() + _getBaseTSAStorage().totalPendingWithdrawals;
  }

  ///////////
  // Views //
  ///////////

  function getBaseTSAAddresses() public view returns (BaseTSAAddresses memory) {
    BaseTSAStorage storage $ = _getBaseTSAStorage();
    return BaseTSAAddresses({
      subAccounts: $.subAccounts,
      auction: $.auction,
      cash: $.cash,
      wrappedDepositAsset: $.wrappedDepositAsset,
      depositAsset: $.depositAsset,
      manager: $.manager,
      matching: $.matching
    });
  }

  function getTSAParams() public view returns (TSAParams memory) {
    return _getBaseTSAStorage().tsaParams;
  }

  function queuedDeposit(uint depositId) public view returns (DepositRequest memory) {
    return _getBaseTSAStorage().queuedDeposit[depositId];
  }

  function queuedWithdrawal(uint withdrawalId) public view returns (WithdrawalRequest memory) {
    return _getBaseTSAStorage().queuedWithdrawals[withdrawalId];
  }

  function totalPendingDeposits() public view returns (uint) {
    return _getBaseTSAStorage().totalPendingDeposits;
  }

  function totalPendingWithdrawals() public view returns (uint) {
    return _getBaseTSAStorage().totalPendingWithdrawals;
  }

  function subAccount() public view returns (uint) {
    return _getBaseTSAStorage().subAccount;
  }

  function shareKeeper(address keeper) public view returns (bool) {
    return _getBaseTSAStorage().shareKeepers[keeper];
  }

  function isBlocked() public view returns (bool) {
    return _isBlocked();
  }

  function lastFeeCollected() public view returns (uint) {
    return _getBaseTSAStorage().lastFeeCollected;
  }

  ///////////////
  // Modifiers //
  ///////////////

  function _isBlocked() internal view returns (bool) {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    return
      $.auction.isAuctionLive($.subAccount) || $.auction.getIsWithdrawBlocked() || $.cash.temporaryWithdrawFeeEnabled();
  }

  modifier onlyShareKeeper() {
    BaseTSAStorage storage $ = _getBaseTSAStorage();

    if (!$.shareKeepers[msg.sender]) {
      revert BTSA_OnlyShareKeeper();
    }
    _;
  }

  modifier checkBlocked() {
    if (_isBlocked()) {
      revert BTSA_Blocked();
    }
    _;
  }

  ////////////
  // Events //
  ////////////

  event TSAParamsUpdated(TSAParams params);
  event ModuleApproved(address module);
  event ShareKeeperUpdated(address keeper, bool isKeeper);

  event DepositInitiated(uint indexed depositId, address indexed recipient, uint amount);
  event DepositProcessed(uint indexed depositId, address indexed recipient, bool success, uint shares);

  event WithdrawalRequested(uint indexed withdrawalId, address indexed beneficiary, uint amount);
  event WithdrawalProcessed(
    uint indexed withdrawalId, address indexed beneficiary, bool complete, uint sharesProcessed, uint amountReceived
  );

  event FeeCollected(address indexed recipient, uint amount, uint timestamp, uint totalSupply);

  error BTSA_InvalidParams();
  error BTSA_MustReceiveShares();
  error BTSA_DepositBelowMinimum();
  error BTSA_DepositCapExceeded();
  error BTSA_DepositAlreadyProcessed();
  error BTSA_InsufficientBalance();
  error BTSA_InvalidWithdrawalAmount();
  error BTSA_ModuleNotPartOfMatching();
  error BTSA_OnlyShareKeeper();
  error BTSA_Blocked();
}
