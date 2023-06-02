// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "lyra-utils/ownership/Owned.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "v2-core/src/interfaces/ICashAsset.sol";
import "v2-core/src/Accounts.sol";
import "v2-core/src/interfaces/IPerpAsset.sol";

import "forge-std/console2.sol";

/**
 * @title Matching
 * @author Lyra
 * @notice Matching contract that allows whitelisted addresses to submit trades for accounts.
 */
contract Matching is EIP712, Owned {
  using DecimalMath for uint;
  using DecimalMath for int;
  using SafeCast for uint;

  struct Match {
    uint accountId1;
    uint accountId2;
    IAsset baseAsset; // baseAsset == perpAsset and quote == empty for perp
    IAsset quoteAsset;
    uint baseSubId;
    uint quoteSubId;
    uint baseAmount; // position size for perp
    uint quoteAmount; // market price for perp
    uint tradeFee;
    bytes signature1;
    bytes signature2;
  } // todo another accountID recieve trade

  struct LimitOrder {
    bool isBid; // is long or short for perp
    uint accountId1;
    uint amount; // For bids, amount is baseAsset. For asks, amount is quoteAsset
    uint limitPrice;
    uint expirationTime;
    uint maxFee;
    uint salt; // todo nonce, mapping nonce -> used
    bytes32 instrumentHash;
  }

  struct VerifiedTrade {
    uint accountId1;
    uint accountId2;
    IAsset baseAsset;
    IAsset quoteAsset;
    uint baseSubId;
    uint quoteSubId;
    uint asset1Amount; // Position size for perps
    uint asset2Amount; // Delta paid for perps
    uint tradeFee;
  }

  struct TransferAsset {
    uint amount;
    uint fromAcc;
    uint toAcc;
    bytes32 assetHash;
  }

  struct MintAccount {
    address owner;
    address manager;
  }

  struct OrderFills {
    uint filledAmount;
    uint totalFees;
  }

  ///@dev Account Id which receives all fees paid
  uint public feeAccountId;

  ///@dev Cooldown seconds a user must wait before withdrawing their account
  uint public withdrawAccountCooldownParam;

  ///@dev Cooldown seconds a user must wait before withdrawing their cash
  uint public withdrawCashCooldownParam;

  ///@dev Cooldown seconds a user must wait before deregister
  uint public deregisterKeyCooldownParam;

  ///@dev Accounts contract address
  IAccounts public immutable accounts;

  ///@dev The cash asset used as quote and for paying fees
  address public cashAsset;

  ///@dev The perp asset
  IPerpAsset public perpAsset;

  ///@dev Mapping of (address => isWhitelistedModule)
  mapping(address => bool) public isWhitelisted;

  ///@dev Mapping of accountId to address
  mapping(uint => address) public accountToOwner;

  ///@dev Mapping of signer address -> owner address -> expiry
  mapping(address => mapping(address => uint)) public sessionKeys; // Allows other addresses to trade on behalf of others

  ///@dev Mapping to track fill amounts and fee total per order
  mapping(bytes32 => OrderFills) public fillAmounts;

  ///@dev Mapping of owner to account withdraw cooldown start time
  mapping(address => uint) public withdrawAccountCooldownMapping;

  ///@dev Mapping of owner to signal cash cooldown start time
  mapping(address => uint) public withdrawCashCooldownMapping;

  ///@dev Order fill typehash containing the limit order hash and trading pair hash, exluding the counterparty for the trade (accountId2)
  bytes32 public constant _LIMITORDER_TYPEHASH =
    keccak256("LimitOrder(bool,uint256,uint256,uint256,uint256,uint256,uint256,bytes32)");

  ///@dev Transfer Asset typehash containing the asset and amount you want to transfer
  bytes32 public constant _TRANSFER_ASSET_TYPEHASH = keccak256("TransferAsset(uint256,uint256,uint256,bytes32");

  ///@dev Mint account typehash containing desired owner address, manager and expiry of the signing address
  bytes32 public constant _MINT_ACCOUNT_TYPEHASH = keccak256("MintAccount(address,address");

  ///@dev Instrument typehash containing the two IAssets and subIds
  bytes32 public constant _INSTRUMENT_TYPEHASH = keccak256("address,address,uint256,uint256");

  ///@dev Asset typehash containing the IAsset and subId
  bytes32 public constant _ASSET_TYPEHASH = keccak256("address,uint256");

  constructor(IAccounts _accounts, address _cashAsset, uint _feeAccountId) EIP712("Matching", "1.0") {
    accounts = _accounts;
    cashAsset = _cashAsset;
    feeAccountId = _feeAccountId;
  }

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice Set which address can submit trades.
   */
  function setWhitelist(address toAllow, bool whitelisted) external onlyOwner {
    isWhitelisted[toAllow] = whitelisted;

    emit AddressWhitelisted(toAllow, whitelisted);
  }

  /**
   * @notice Set the fee account ID
   */
  function setFeeAccountId(uint feeId) external onlyOwner {
    feeAccountId = feeId;

    emit FeeAccountIdSet(feeId);
  }

  /**
   * @notice Set the withdraw account cooldown seconds.
   */
  function setWithdrawAccountCooldown(uint cooldown) external onlyOwner {
    withdrawAccountCooldownParam = cooldown;

    emit WithdrawAccountCooldownParamSet(cooldown);
  }

  /**
   * @notice Set the withdraw cash cooldown seconds.
   */
  function setWithdrawCashCooldown(uint cooldown) external onlyOwner {
    withdrawCashCooldownParam = cooldown;

    emit WithdrawCashCooldownParamSet(cooldown);
  }
  /**
   * @notice Set the deregister session key cooldown seconds.
   */

  function setSessionKeyCooldown(uint cooldown) external onlyOwner {
    deregisterKeyCooldownParam = cooldown;

    emit DeregisterKeyCooldownParamSet(cooldown);
  }

  /**
   * @notice set the PerpAsset that is compatible for trading
   */
  function setPerpAsset(IPerpAsset _perpAsset) external onlyOwner {
    perpAsset = _perpAsset;

    emit PerpAssetSet(_perpAsset);
  }

  /////////////////////////////
  //  Whitelisted Functions  //
  /////////////////////////////

  /**
   * @notice Allows whitelisted addresses to submit trades
   * @param matches Array of Match structs containing the amounts and signatures for each trade
   * @param orders1 Array of LimitOrder structs
   * @param orders2 Array of LimitOrder structs
   */
  function submitTrades(Match[] calldata matches, LimitOrder[] calldata orders1, LimitOrder[] calldata orders2)
    external
    onlyWhitelisted
  {
    if (matches.length != orders1.length || orders1.length != orders2.length) {
      revert M_ArrayLengthMismatch(matches.length, orders1.length, orders2.length);
    }

    VerifiedTrade[] memory matchedOrders = new VerifiedTrade[](matches.length);
    for (uint i = 0; i < matches.length; i++) {
      matchedOrders[i] = _verifyTrade(matches[i], orders1[i], orders2[i]);
    }

    _submitAssetTransfers(matchedOrders);
  }

  /**
   * @dev Batch transfers assets from one account to another.
   * Can only be called by an address that is currently whitelisted.
   *
   * @param transfers The details of the asset transfers to be made.
   * @param signatures The signed messages from the owner or permissioned accounts.
   */
  function submitTransfers(
    TransferAsset[] memory transfers,
    IAsset[] memory assets,
    uint[] memory subIds,
    bytes[] memory signatures
  ) external onlyWhitelisted {
    if (transfers.length != signatures.length || transfers.length != assets.length || transfers.length != subIds.length)
    {
      revert M_TransferArrayLengthMismatch(transfers.length, assets.length, subIds.length, signatures.length);
    }

    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](transfers.length);
    for (uint i = 0; i < transfers.length; i++) {
      transferBatch[i] = _verifyTransferAsset(transfers[i], assets[i], subIds[i], 0, signatures[i]);
    }

    accounts.submitTransfers(transferBatch, "");
  }

  /**
   * @notice Allows whitelisted addresses to force close an account with no cooldown delay.
   */
  function forceCloseCLOBAccount(uint accountId) external onlyWhitelisted {
    accounts.transferFrom(address(this), accountToOwner[accountId], accountId);
    delete accountToOwner[accountId];

    emit ClosedCLOBAccount(accountId);
  }

  //////////////////////////
  //  External Functions  //
  //////////////////////////

  ///////////////////////
  //  Account actions  //
  ///////////////////////
  /**
   * @notice Allows user to open an account by transferring their account NFT to this contract.
   * @dev User must approve contract first.
   * @param accountId The users' accountId
   */
  function openCLOBAccount(uint accountId) external {
    accounts.transferFrom(msg.sender, address(this), accountId);
    accountToOwner[accountId] = msg.sender;

    emit OpenedCLOBAccount(accountId);
  }

  /**
   * @notice Allows signature to create new subAccount, open a CLOB account, and transfer asset.
   * @dev Signature should have signed the transfer.
   */
  function mintAccountAndTransfer(
    MintAccount memory newAccount,
    TransferAsset memory transfer,
    IAsset asset,
    uint subId,
    bytes memory signature
  ) external returns (uint newId) {
    address toAllow = _recoverAddress(_getTransferHash(transfer), signature);
    newId = _mintCLOBAccount(newAccount, toAllow);

    IAccounts.AssetTransfer memory assetTransfer = _verifyTransferAsset(transfer, asset, subId, newId, signature);
    accounts.submitTransfer(assetTransfer, "");

    emit OpenedCLOBAccount(newId);
  }

  /**
   * @notice Activates the cooldown period to withdraw account.
   */
  function requestCloseCLOBAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
    withdrawAccountCooldownMapping[msg.sender] = block.timestamp;
    emit AccountCooldown(msg.sender);
  }

  /**
   * @notice Allows user to close their account by transferring their account NFT back.
   * @dev User must have previously called `requestCloseCLOBAccount()` and waited for the cooldown to elapse.
   * @param accountId The users' accountId
   */
  function completeCloseCLOBAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
    if (withdrawAccountCooldownMapping[msg.sender] + (withdrawAccountCooldownParam) > block.timestamp) {
      revert M_CooldownNotElapsed(
        withdrawAccountCooldownMapping[msg.sender] + (withdrawAccountCooldownParam) - block.timestamp
      );
    }

    accounts.transferFrom(address(this), msg.sender, accountId);
    withdrawAccountCooldownMapping[msg.sender] = 0;
    delete accountToOwner[accountId];

    emit ClosedCLOBAccount(accountId);
  }

  ////////////////////
  //  Session Keys  //
  ////////////////////

  /**
   * @notice Allows owner to register the public address associated with their session key to their accountId.
   * @dev Registered address gains owner address permission to the subAccount until expiry.
   * @param expiry When the access to the owner address expires
   */
  function registerSessionKey(address toAllow, uint expiry) external {
    sessionKeys[toAllow][msg.sender] = expiry;

    emit SessionKeyRegistered(msg.sender, toAllow);
  }

  /**
   * @notice Allows owner to deregister a session key from their account.
   * @dev Expires the sessionKey after the cooldown.
   */
  function requestDeregisterSessionKey(address sessionKey) external {
    // Ensure the session key has not expired
    if (sessionKeys[sessionKey][msg.sender] < block.timestamp) revert M_SessionKeyInvalid(sessionKey);

    sessionKeys[sessionKey][msg.sender] = block.timestamp + deregisterKeyCooldownParam;
    emit SessionKeyCooldown(msg.sender, sessionKey);
  }

  /////////////////////
  //  Withdraw Cash  //
  /////////////////////

  /**
   * @notice Activates the cooldown period to withdraw cash.
   */
  function requestWithdrawCash(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
    withdrawCashCooldownMapping[msg.sender] = block.timestamp;
    emit CashCooldown(msg.sender);
  }

  /**
   * @notice Withdraw cash from an accountId using a signature.
   * @dev Owner address must have requested for withdrawal first and waited for the cooldown to elapse.
   */
  function completeWithdrawCash(TransferAsset memory transfer, bytes memory signature) external {
    if (withdrawCashCooldownMapping[accountToOwner[transfer.fromAcc]] + (withdrawCashCooldownParam) > block.timestamp) {
      revert M_CooldownNotElapsed(
        withdrawCashCooldownMapping[accountToOwner[transfer.fromAcc]] + (withdrawCashCooldownParam) - block.timestamp
      );
    }
    // Verify signatures
    bytes32 transferHash = _getTransferHash(transfer);
    if (!_verifySignature(transfer.fromAcc, transferHash, signature)) {
      revert M_InvalidSignature(accountToOwner[transfer.fromAcc]);
    }

    ICashAsset(cashAsset).withdraw(transfer.fromAcc, transfer.amount, accountToOwner[transfer.fromAcc]);
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  /**
   * @dev Mints a new CLOB Account by creating a subAccount
   * @param newAccount the details of the new account to be minted. The MintAccount struct contains the owner of the new account and the manager of the new account.
   * @param toAllow is the address to be allowed for executing functions on behalf of the account owner
   * @return newId returns the newly created account ID
   */
  function _mintCLOBAccount(MintAccount memory newAccount, address toAllow) internal returns (uint newId) {
    if (sessionKeys[toAllow][newAccount.owner] < block.timestamp) revert M_SessionKeyInvalid(toAllow);
    newId = accounts.createAccount(address(this), IManager(newAccount.manager));
    accountToOwner[newId] = newAccount.owner;
  }

  ////////////////////////////
  //  Verify trade details  //
  ////////////////////////////

  /**
   * @notice Allows whitelisted addresses to submit trades.
   * @param matchDetails Contains the details of the order match.
   * @param order1 Contains the details of one side of the order.
   * @param order2 Contains the details of the other side of the order.
   *
   * @return matchedOrder Returns details of the trade to be executed.
   */
  function _verifyTrade(Match memory matchDetails, LimitOrder memory order1, LimitOrder memory order2)
    internal
    returns (VerifiedTrade memory matchedOrder)
  {
    // Verify trading pair and user signatures
    _verifyTradeSignatures(order1, order2, matchDetails);

    // Validate order match and parameters
    _validateOrderDetails(order1, order2, matchDetails);

    // Check if it is a perp or option trade
    bool isPerpTrade = _isPerpTrade(address(matchDetails.baseAsset), address(matchDetails.quoteAsset));

    // todo if perp validateLimitPrice flow slightly different
    if (isPerpTrade) {
      _validateLimitPrice(order1.isBid, order1.limitPrice, matchDetails.quoteAmount);
      _validateLimitPrice(order2.isBid, order2.limitPrice, matchDetails.quoteAmount);
    } else {
      uint calculatedPrice = matchDetails.baseAmount.divideDecimal(matchDetails.quoteAmount);
      // Verify the calculated price is within the limit price
      _validateLimitPrice(order1.isBid, order1.limitPrice, calculatedPrice);
      _validateLimitPrice(order2.isBid, order2.limitPrice, calculatedPrice);
    }

    // Verify and update fill/fee amounts for both orders
    _verifyAndUpdateFillAllowance(
      order1.amount,
      order2.amount,
      order1.maxFee,
      order2.maxFee,
      matchDetails.tradeFee,
      matchDetails.baseAmount,
      matchDetails.quoteAmount,
      _getOrderHash(order1),
      _getOrderHash(order2)
    );

    // Once all parameters are verified and validated we return the order details to be executed
    return VerifiedTrade({
      accountId1: matchDetails.accountId1,
      accountId2: matchDetails.accountId2,
      baseAsset: matchDetails.baseAsset,
      quoteAsset: matchDetails.quoteAsset,
      baseSubId: matchDetails.baseSubId,
      quoteSubId: matchDetails.quoteSubId,
      asset1Amount: matchDetails.baseAmount,
      asset2Amount: matchDetails.quoteAmount,
      tradeFee: matchDetails.tradeFee
    });
  }

  /**
   * @notice Verifies the transfer of an asset from one account to another.
   * Can only be called by an address that is currently whitelisted.
   *
   * @param transfer The details of the asset transfer to be made.
   * @param signature The signed message from the owner account.
   * @param asset The asset to be transferred, used to check against the signature.
   * @param subId The subId of the asset to be transferred, used to check against the signature.
   * @param newId If not 0, the newly minted accountId to transfer to.
   */
  function _verifyTransferAsset(
    TransferAsset memory transfer,
    IAsset asset,
    uint subId,
    uint newId,
    bytes memory signature
  ) internal view returns (IAccounts.AssetTransfer memory verifiedTransfer) {
    // Verify the asset hash
    bytes32 assetHash = _getAssetHash(asset, subId);
    if (transfer.assetHash != assetHash) revert M_InvalidAssetHash(transfer.assetHash, assetHash);

    // Verify signature is signed by the account owner or permitted address
    bytes32 transferHash = _getTransferHash(transfer);
    if (!_verifySignature(transfer.fromAcc, transferHash, signature)) {
      revert M_InvalidSignature(accountToOwner[transfer.fromAcc]);
    }

    // If the address is not owner ensure permission has not expired for the 'toAcc'
    address sessionKeyAddress = _recoverAddress(transferHash, signature);

    // If toAcc is not empty we check for permission expiry, if not empty we fill the transfer with the newId
    if (transfer.toAcc != 0) {
      address toAccOwner = accountToOwner[transfer.toAcc];
      if (sessionKeyAddress != toAccOwner && sessionKeys[sessionKeyAddress][toAccOwner] < block.timestamp) {
        revert M_SessionKeyInvalid(sessionKeyAddress);
      }
      // Return normal asset transfer using transfer details
      return IAccounts.AssetTransfer({
        fromAcc: transfer.fromAcc,
        toAcc: transfer.toAcc,
        asset: asset,
        subId: subId,
        amount: transfer.amount.toInt256(),
        assetData: bytes32(0)
      });
    } else if (newId != 0) {
      // Return asset transfer to the newly minted account
      return IAccounts.AssetTransfer({
        fromAcc: transfer.fromAcc,
        toAcc: newId,
        asset: asset,
        subId: subId,
        amount: transfer.amount.toInt256(),
        assetData: bytes32(0)
      });
    } else {
      revert M_TransferToZeroAccount();
    }
  }

  /**
   * @notice Verifies the instrument hash and trade against the signatures provided in the match details.
   */
  function _verifyTradeSignatures(LimitOrder memory order1, LimitOrder memory order2, Match memory matchDetails)
    internal
    view
  {
    // Verify trading pair
    bytes32 instrumentHash = _getInstrumentHash(
      matchDetails.baseAsset, matchDetails.quoteAsset, matchDetails.baseSubId, matchDetails.quoteSubId
    );
    if (order1.instrumentHash != instrumentHash) revert M_InvalidTradingPair(order1.instrumentHash, instrumentHash);
    if (order2.instrumentHash != instrumentHash) revert M_InvalidTradingPair(order2.instrumentHash, instrumentHash);

    bytes32 order1Hash = _getOrderHash(order1);
    bytes32 order2Hash = _getOrderHash(order2);

    // Verify signatures
    if (!_verifySignature(order1.accountId1, order1Hash, matchDetails.signature1)) {
      revert M_InvalidSignature(accountToOwner[order1.accountId1]);
    }
    if (!_verifySignature(order2.accountId1, order2Hash, matchDetails.signature2)) {
      revert M_InvalidSignature(accountToOwner[order2.accountId1]);
    }
  }

  /**
   * @notice Validates the order details including accounts, trade amount, assets and price.
   */
  function _validateOrderDetails(LimitOrder memory order1, LimitOrder memory order2, Match memory matchDetails)
    internal
    view
  {
    // Ensure the accountId and taker are different accounts
    if (matchDetails.accountId1 == matchDetails.accountId2) revert M_CannotTradeToSelf(matchDetails.accountId1);

    // Ensure some amount is traded
    if (order1.amount == 0) revert M_ZeroAmountToTrade();
    if (order2.amount == 0) revert M_ZeroAmountToTrade();

    // Ensure order has not expired
    if (block.timestamp > order1.expirationTime) revert M_OrderExpired(block.timestamp, order1.expirationTime);
    if (block.timestamp > order2.expirationTime) revert M_OrderExpired(block.timestamp, order2.expirationTime);

    // Check trade fee < maxFee
    if (matchDetails.tradeFee > order1.maxFee) revert M_TradeFeeExceedsMaxFee(matchDetails.tradeFee, order1.maxFee);
    if (matchDetails.tradeFee > order2.maxFee) revert M_TradeFeeExceedsMaxFee(matchDetails.tradeFee, order2.maxFee);

    // Check for zero trade amount
    if (matchDetails.baseAmount == 0 && matchDetails.quoteAmount == 0) {
      revert M_ZeroAmountToTrade();
    }

    // Verify that the two assets are unique
    if (order1.isBid == order2.isBid) revert M_TradingSameSide();
    if (matchDetails.baseAsset == matchDetails.quoteAsset) {
      revert M_CannotTradeSameAsset(matchDetails.baseAsset, matchDetails.quoteAsset);
    }
  }

  /**
   * @notice Updates fill and fee allowances for a trade if the amounts are valid.
   */
  function _verifyAndUpdateFillAllowance(
    uint order1Amount,
    uint order2Amount,
    uint order1MaxFee,
    uint order2MaxFee,
    uint tradeFee,
    uint baseAmount,
    uint quoteAmount,
    bytes32 order1Hash,
    bytes32 order2Hash
  ) internal {
    // Ensure the orders have not been completely filled yet
    uint remainingAmount1 = order1Amount - fillAmounts[order1Hash].filledAmount;
    uint remainingAmount2 = order2Amount - fillAmounts[order2Hash].filledAmount;

    if (remainingAmount1 < baseAmount) {
      revert M_InsufficientFillAmount(1, remainingAmount1, baseAmount);
    }
    if (remainingAmount2 < quoteAmount) {
      revert M_InsufficientFillAmount(2, remainingAmount2, quoteAmount);
    }

    // Ensure trade fee < maxFee (cumulative paid)
    uint remainingFee1 = order1MaxFee - fillAmounts[order1Hash].totalFees;
    uint remainingFee2 = order2MaxFee - fillAmounts[order1Hash].totalFees;
    if (tradeFee > remainingFee1) revert M_TradeFeeExceedsMaxFee(tradeFee, remainingFee1);
    if (tradeFee > remainingFee2) revert M_TradeFeeExceedsMaxFee(tradeFee, remainingFee2);

    // Update the filled amounts for the orders
    fillAmounts[order1Hash].filledAmount += baseAmount;
    fillAmounts[order2Hash].filledAmount += quoteAmount;

    fillAmounts[order1Hash].totalFees += tradeFee;
    fillAmounts[order2Hash].totalFees += tradeFee;
  }

  /**
   * @notice Calculates the execution price is within the limit price.
   */
  function _validateLimitPrice(bool isLong, uint limitPrice, uint marketPrice) internal pure {
    // If you want to long but the price is above your limit
    if (isLong && marketPrice > limitPrice) {
      revert M_BidPriceAboveLimit(limitPrice, marketPrice);
    } else if (!isLong && marketPrice < limitPrice) {
      // If you want to short but the price is below your limit
      revert M_AskPriceBelowLimit(limitPrice, marketPrice);
    }
  }

  // Difference between the perp Asset index price and the market price
  function _calculatePerpDelta(uint marketPrice, uint positionSize) internal returns (int delta) {
    // int index = perpAsset.getIndexPriceSpot(); // implemented in proto1/sprint7
    int index = 1800e18;

    // if ()
    // delta = (marketPrice.toInt256() - index).multiplyDecimal(positionSize);
  }

  function _submitAssetTransfers(VerifiedTrade[] memory orders) internal {
    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](orders.length * 4);

    for (uint i = 0; i < orders.length; i++) {
      // Transfer assets between the two accounts
      transferBatch[i] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId1,
        toAcc: orders[i].accountId2,
        asset: orders[i].baseAsset,
        subId: orders[i].baseSubId,
        amount: orders[i].asset1Amount.toInt256(),
        assetData: bytes32(0)
      });

      transferBatch[i + 1] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId2,
        toAcc: orders[i].accountId1,
        asset: orders[i].quoteAsset,
        subId: orders[i].quoteSubId,
        amount: orders[i].asset2Amount.toInt256(),
        assetData: bytes32(0)
      });

      // Charge fee from both accounts to the feeAccount
      transferBatch[i + 2] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId1,
        toAcc: feeAccountId,
        asset: IAsset(cashAsset),
        subId: 0,
        amount: orders[i].tradeFee.toInt256(),
        assetData: bytes32(0)
      });

      transferBatch[i + 3] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId2,
        toAcc: feeAccountId,
        asset: IAsset(cashAsset),
        subId: 0,
        amount: orders[i].tradeFee.toInt256(),
        assetData: bytes32(0)
      });
    }

    accounts.submitTransfers(transferBatch, ""); // todo fill with oracle data
  }

  function _isPerpTrade(address baseAsset, address quoteAsset) internal view returns (bool) {
    if (baseAsset == address(perpAsset) && quoteAsset == address(0)) return true;
    return false;
  }

  /**
   * @notice Verify signature against owner address or permissioned address.
   */
  function _verifySignature(uint accountId, bytes32 structuredHash, bytes memory signature)
    internal
    view
    returns (bool)
  {
    if (
      SignatureChecker.isValidSignatureNow(accountToOwner[accountId], _hashTypedDataV4(structuredHash), signature)
        == true
    ) {
      return true;
    } else {
      address signer = _recoverAddress(structuredHash, signature);
      if (sessionKeys[signer][accountToOwner[accountId]] > block.timestamp) {
        return true;
      }
      return false;
    }
  }

  /////////////////////////
  //  Hashing Functions  //
  /////////////////////////

  function _getInstrumentHash(IAsset baseAsset, IAsset quoteAsset, uint baseSubId, uint quoteSubId)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(abi.encode(_INSTRUMENT_TYPEHASH, baseAsset, quoteAsset, baseSubId, quoteSubId));
  }

  function _getOrderHash(LimitOrder memory order) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        _LIMITORDER_TYPEHASH,
        order.isBid,
        order.accountId1,
        order.amount,
        order.limitPrice,
        order.expirationTime,
        order.maxFee,
        order.salt,
        order.instrumentHash
      )
    );
  }

  function _getTransferHash(TransferAsset memory transfer) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(_TRANSFER_ASSET_TYPEHASH, transfer.amount, transfer.fromAcc, transfer.toAcc, transfer.assetHash)
    );
  }

  function _getAssetHash(IAsset asset, uint subId) internal pure returns (bytes32) {
    return keccak256(abi.encode(_ASSET_TYPEHASH, address(asset), subId));
  }

  function _recoverAddress(bytes32 hash, bytes memory signature) internal view returns (address) {
    (address recovered,) = ECDSA.tryRecover(_hashTypedDataV4(hash), signature);
    return recovered;
  }

  ///////////
  // Views //
  ///////////

  /**
   * @dev get domain separator for signing
   */
  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  function getOrderHash(LimitOrder calldata order) external pure returns (bytes32) {
    return _getOrderHash(order);
  }

  function getTransferHash(TransferAsset calldata transfer) external pure returns (bytes32) {
    return _getTransferHash(transfer);
  }

  function getAssetHash(IAsset asset, uint subId) external pure returns (bytes32) {
    return _getAssetHash(asset, subId);
  }

  function getInstrument(IAsset baseAsset, IAsset quoteAsset, uint baseSubId, uint quoteSubId)
    external
    pure
    returns (bytes32)
  {
    return _getInstrumentHash(baseAsset, quoteAsset, baseSubId, quoteSubId);
  }

  function verifySignature(uint accountId, bytes32 orderHash, bytes memory signature) external view returns (bool) {
    return _verifySignature(accountId, orderHash, signature);
  }

  /////////////////
  //  Modifiers  //
  /////////////////

  modifier onlyWhitelisted() {
    if (!isWhitelisted[msg.sender]) revert M_NotWhitelisted();
    _;
  }

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when an address is added to / remove from the whitelist
   */
  event AddressWhitelisted(address user, bool isWhitelisted);

  /**
   * @dev Emitted when the perp asset is set
   */
  event PerpAssetSet(IPerpAsset perpAsset);

  /**
   * @dev Emitted when the fee account ID is set.
   */
  event FeeAccountIdSet(uint feeAccountId);

  /**
   * @dev Emitted when a trade is executed
   */
  event Trade(bytes32 indexed OrderParams, uint fillAmount);

  /**
   * @dev Emitted when a user requests account withdrawal and begins the cooldown
   */
  event AccountCooldown(address user);

  /**
   * @dev Emitted when a user requests cash withdrawal and begins the cooldown
   */
  event CashCooldown(address user);

  /**
   * @dev Emitted when a user requests to deregister a session key
   */
  event SessionKeyCooldown(address owner, address sessionKeyPublicAddress);

  /**
   * @dev Emitted when withdraw account cooldown is set
   */
  event WithdrawAccountCooldownParamSet(uint cooldown);

  /**
   * @dev Emitted when withdraw cash cooldown is set
   */
  event WithdrawCashCooldownParamSet(uint cooldown);

  /**
   * @dev Emitted when the deregister session key cooldown is set
   */
  event DeregisterKeyCooldownParamSet(uint cooldown);

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event OpenedCLOBAccount(uint accountId);

  /**
   * @dev Emitted when a CLOB account is closed.
   */
  event ClosedCLOBAccount(uint accountId);

  /**
   * @dev Emitted when a session key is registered to an owner account.
   */
  event SessionKeyRegistered(address owner, address sessionKey);

  ////////////
  // Errors //
  ////////////

  error M_InvalidSignature(address signer);
  error M_InvalidTradingPair(bytes32 suppliedHash, bytes32 matchHash);
  error M_InvalidAssetHash(bytes32 suppliedHash, bytes32 assetHash);
  error M_NotWhitelisted();
  error M_NotOwnerAddress(address sender, address owner);
  error M_InvalidAccountOwner(address accountIdOwner, address inputOwner);
  error M_CannotTradeToSelf(uint accountId);
  error M_InsufficientFillAmount(uint orderNumber, uint remainingFill, uint requestedFill);
  error M_OrderExpired(uint blockTimestamp, uint expirationTime);
  error M_ZeroAmountToTrade();
  error M_TradingSameSide();
  error M_ArrayLengthMismatch(uint length1, uint length2, uint length3);
  error M_TransferArrayLengthMismatch(uint transfers, uint assets, uint subIds, uint signatues);
  error M_AskPriceBelowLimit(uint limitPrice, uint calculatedPrice);
  error M_BidPriceAboveLimit(uint limitPrice, uint calculatedPrice);
  error M_CannotTradeSameAsset(IAsset baseAsset, IAsset quoteAsset);
  error M_TradeFeeExceedsMaxFee(uint tradeFee, uint maxFee);
  error M_CooldownNotElapsed(uint secondsLeft);
  error M_SessionKeyInvalid(address sessionKeyPublicAddress);
  error M_TransferToZeroAccount();
}
