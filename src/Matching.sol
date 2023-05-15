// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "lyra-utils/ownership/Owned.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "v2-core/src/Accounts.sol";
import "forge-std/console2.sol";

// todo sub signers
/**
 * @title Matching
 * @author Lyra
 * @notice Matching contract that allows whitelisted addresses to submit trades for accounts.
 */
contract Matching is EIP712, Owned {
  using DecimalMath for uint;
  using SafeCast for uint;

  struct Match {
    uint baseAmount;
    uint quoteAmount;
    IAsset baseAsset;
    IAsset quoteAsset;
    uint baseSubId;
    uint quoteSubId;
    uint tradeFee;
    bytes signature1;
    bytes signature2;
  }

  // todo perp asset data
  struct LimitOrder {
    bool isBid;
    uint accountId1;
    uint accountId2;
    uint amount; // For bids, amount is baseAsset. For asks, amount is quoteAsset
    uint limitPrice;
    uint expirationTime;
    uint maxFee;
    uint salt; // todo optional for users with duplicate orders
    bytes32 tradingPair;
  }

  struct VerifiedOrder {
    uint accountId1;
    uint accountId2;
    IAsset baseAsset;
    IAsset quoteAsset;
    uint baseSubId;
    uint quoteSubId;
    uint asset1Amount;
    uint asset2Amount;
    uint accountId1Fee;
    uint accountId2Fee;
  }

  ///@dev Account Id which receives all fees paid
  uint public feeAccountId;

  ///@dev Accounts contract address
  IAccounts public immutable accounts;

  ///@dev The cash asset used as quote and for paying fees
  IAsset public cashAsset;

  ///@dev Mapping of (address => isWhitelistedModule)
  mapping(address => bool) public isWhitelisted;

  ///@dev Mapping of accountId to address
  mapping(uint => address) public accountToOwner;

  ///@dev Mapping to track fill amounts per order
  mapping(bytes32 => uint) public fillAmounts;

  ///@dev Mapping to track frozen accounts
  mapping(address => bool) public isFrozen;

  ///@dev Order fill typehash containing the limit order hash and trading pair hash, exluding the counterparty for the trade (accountId2)
  bytes32 public constant _LIMITORDER_TYPEHASH =
    keccak256("LimitOrder(bool,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bytes32)");

  ///@dev Trading pair typehash containing the two IAssets and subIds
  bytes32 public constant _TRADING_PAIR_TYPEHASH = keccak256("address,address,uint256,uint256");

  constructor(IAccounts _accounts, IAsset _cashAsset, uint _feeAccountId) EIP712("Matching", "1.0") {
    accounts = _accounts;
    cashAsset = _cashAsset;
    feeAccountId = _feeAccountId;
  }

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice set which address can submit trades
   */
  function setWhitelist(address toAllow, bool whitelisted) external onlyOwner {
    isWhitelisted[toAllow] = whitelisted;

    emit AddressWhitelisted(toAllow, whitelisted);
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

    VerifiedOrder[] memory matchedOrders = new VerifiedOrder[](matches.length);
    for (uint i = 0; i < matches.length; i++) {
      matchedOrders[i] = _trade(matches[i], orders1[i], orders2[i]); // if one trade reverts everything reverts
    }

    _submitAssetTransfers(matchedOrders);
  }

  //////////////////////////
  //  External Functions  //
  //////////////////////////

  /**
   * @notice Allows user to open an account by transferring their account NFT to this contract.
   * @dev User must approve contract first.
   * @param accountId The users' accountId
   */
  // todo do we want to allow users to open account or only approval -> OB opens account flow?
  function openCLOBAccount(uint accountId) external {
    accounts.transferFrom(msg.sender, address(this), accountId);
    accountToOwner[accountId] = msg.sender;
  }

  /**
   * @notice Allows user to close their account by transferring their account NFT back.
   * @param accountId The users' accountId
   */
  function closeCLOBAccount(uint accountId) external {
    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);

    accounts.transferFrom(address(this), msg.sender, accountId);
    delete accountToOwner[accountId];
  }

  // todo withdrawals / key to give permission to trade for an address

  /**
   * @notice Allows sender to 'freeze' their account which blocks all trading actions.
   * @param freeze Boolean on whether to freeze or unfreeze your account
   */
  function freezeAccount(bool freeze) external {
    // todo add signal for withdrawal with time delay
    isFrozen[msg.sender] = freeze;
    emit AccountFrozen(msg.sender, freeze);
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  /**
   * @notice Allows whitelisted addresses to submit trades
   *
   */
  function _trade(Match memory matchDetails, LimitOrder memory order1, LimitOrder memory order2)
    internal
    returns (VerifiedOrder memory matchedOrder)
  {
    // Verify trading pair
    bytes32 tradingPair =
      _getTradingPairHash(matchDetails.baseAsset, matchDetails.quoteAsset, matchDetails.baseSubId, matchDetails.quoteSubId);
    if (order1.tradingPair != tradingPair) revert M_InvalidTradingPair(order1.tradingPair, tradingPair);
    if (order2.tradingPair != tradingPair) revert M_InvalidTradingPair(order2.tradingPair, tradingPair);

    bytes32 order1Hash = _getOrderHash(order1);
    bytes32 order2Hash = _getOrderHash(order2);

    // Verify signatures
    if (!_verifySignature(order1.accountId1, order1Hash, matchDetails.signature1)) {
      revert M_InvalidSignature(accountToOwner[order1.accountId1]);
    }
    if (!_verifySignature(order2.accountId1, order2Hash, matchDetails.signature2)) {
      revert M_InvalidSignature(accountToOwner[order2.accountId1]);
    }

    // Validate parameters for both orders
    _validateOrderParams(order1);
    _validateOrderParams(order2);

    // Validate order match details
    _validateOrderMatch(order1, order2, matchDetails);

    // Verify and update fill amounts for both orders
    _verifyAndUpdateFillAllowance(order1.amount, order2.amount, matchDetails.baseAmount, matchDetails.quoteAmount, order1Hash, order2Hash);

    return VerifiedOrder({
      accountId1: order1.accountId1,
      accountId2: order1.accountId2,
      baseAsset: matchDetails.baseAsset,
      quoteAsset: matchDetails.quoteAsset,
      baseSubId: matchDetails.baseSubId,
      quoteSubId: matchDetails.quoteSubId,
      asset1Amount: matchDetails.baseAmount,
      asset2Amount: matchDetails.quoteAmount,
      accountId1Fee: matchDetails.tradeFee,
      accountId2Fee: matchDetails.tradeFee
    });
  }

  function _validateOrderMatch(LimitOrder memory order1, LimitOrder memory order2, Match memory matchDetails)
    internal
    pure
  {
    // Check trade fee < maxFee
    if (matchDetails.tradeFee > order1.maxFee) revert M_TradeFeeExceedsMaxFee(matchDetails.tradeFee, order1.maxFee);
    if (matchDetails.tradeFee > order2.maxFee) revert M_TradeFeeExceedsMaxFee(matchDetails.tradeFee, order2.maxFee);

    // Check for zero trade amount
    if (matchDetails.baseAmount == 0 && matchDetails.baseAmount == matchDetails.quoteAmount) revert M_ZeroAmountToTrade();

    // Ensure the trade is from one accountId to another accountId
    if (order1.accountId1 != order2.accountId2 || order1.accountId2 != order2.accountId1) {
      revert M_AccountIdsDoNotMatch(order1.accountId1, order2.accountId2, order1.accountId2, order2.accountId1);
    }

    // Verify that the two assets are unique
    if (order1.isBid == order2.isBid) revert M_TradingSameSide();
    if (matchDetails.baseAsset == matchDetails.quoteAsset) {
      revert M_CannotTradeSameAsset(matchDetails.baseAsset, matchDetails.quoteAsset);
    }

    // Verify the calculated price is within the limit price
    uint calculatedPrice = matchDetails.baseAmount.divideDecimal(matchDetails.quoteAmount);
    _checkLimitPrice(order1.isBid, order1.limitPrice, calculatedPrice);
    _checkLimitPrice(order2.isBid, order2.limitPrice, calculatedPrice);
  }

  function _validateOrderParams(LimitOrder memory order) internal view {
    // Ensure the accountId and taker are different accounts
    if (order.accountId1 == order.accountId2) revert M_CannotTradeToSelf(order.accountId1);

    // Ensure the accountId and taker accounts are not frozen
    if (isFrozen[accountToOwner[order.accountId1]]) revert M_AccountFrozen(accountToOwner[order.accountId1]);
    if (isFrozen[accountToOwner[order.accountId2]]) revert M_AccountFrozen(accountToOwner[order.accountId2]);

    // Ensure some amount is traded
    if (order.amount == 0) revert M_ZeroAmountToTrade();

    // Ensure order has not expired
    if (block.timestamp > order.expirationTime) revert M_OrderExpired(block.timestamp, order.expirationTime);
  }

  function _verifyAndUpdateFillAllowance(uint order1Amount, uint order2Amount, uint baseAmount, uint quoteAmount, bytes32 order1Hash, bytes32 order2Hash) internal {
    // Ensure the orders have not been completely filled yet
    uint remainingAmount1 = order1Amount - fillAmounts[order1Hash];
    uint remainingAmount2 = order2Amount - fillAmounts[order2Hash];

    if (remainingAmount1 < baseAmount) {
      revert M_InsufficientFillAmount(1, remainingAmount1, baseAmount);
    }
    if (remainingAmount2 < quoteAmount) {
      revert M_InsufficientFillAmount(2, remainingAmount2, quoteAmount);
    }

    // Update the filled amounts for the orders
    fillAmounts[order1Hash] += baseAmount;
    fillAmounts[order2Hash] += quoteAmount;
  }

  function _checkLimitPrice(bool isBid, uint limitPrice, uint calculatedPrice) internal pure {
    // If you want to buy but the price is above your limit
    if (isBid && calculatedPrice > limitPrice) {
      revert M_BidPriceAboveLimit(limitPrice, calculatedPrice);
    } else if (!isBid && calculatedPrice < limitPrice) {
      // If you are selling but the price is below your limit
      revert M_AskPriceBelowLimit(limitPrice, calculatedPrice);
    }
  }

  function _submitAssetTransfers(VerifiedOrder[] memory orders) internal {
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
        asset: cashAsset,
        subId: 0,
        amount: orders[i].accountId1Fee.toInt256(),
        assetData: bytes32(0)
      });

      transferBatch[i + 3] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId2,
        toAcc: feeAccountId,
        asset: cashAsset,
        subId: 0,
        amount: orders[i].accountId2Fee.toInt256(),
        assetData: bytes32(0)
      });
    }

    accounts.submitTransfers(transferBatch, ""); // todo fill with oracle data
  }

  function _verifySignature(uint accountId, bytes32 orderHash, bytes memory signature) internal view returns (bool) {
    return SignatureChecker.isValidSignatureNow(accountToOwner[accountId], _hashTypedDataV4(orderHash), signature);
  }

  function _getTradingPairHash(IAsset baseAsset, IAsset quoteAsset, uint baseSubId, uint quoteSubId) internal pure returns (bytes32) {
    return keccak256(abi.encode(_TRADING_PAIR_TYPEHASH, baseAsset, quoteAsset, baseSubId, quoteSubId));
  }

  function _getOrderHash(LimitOrder memory order) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        _LIMITORDER_TYPEHASH,
        order.isBid,
        order.accountId1,
        0, // Order hash does not include the counterparty
        order.amount,
        order.limitPrice,
        order.expirationTime,
        order.maxFee,
        order.salt,
        order.tradingPair
      )
    );
  }

  //////////
  // View //
  //////////

  /**
   * @dev get domain separator for signing
   */
  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  function getOrderHash(LimitOrder calldata order) external pure returns (bytes32) {
    return _getOrderHash(order);
  }

  function getTradingPair(IAsset baseAsset, IAsset quoteAsset, uint baseSubId, uint quoteSubId) external pure returns (bytes32) {
    return _getTradingPairHash(baseAsset, quoteAsset, baseSubId, quoteSubId);
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
   * @dev Emitted when a trade is executed
   */
  event Trade(bytes32 indexed OrderParams, uint fillAmount);

  /**
   * @dev Emitted when a user's account is frozen or unfrozen
   */
  event AccountFrozen(address account, bool isFrozen);

  /**
   * @dev Emitted when the base fee rate is updated for an asset
   */
  event FeeRateUpdated(IAsset asset, uint newFeeRate);

  ////////////
  // Errors //
  ////////////

  error M_InvalidSignature(address signer);
  error M_InvalidTradingPair(bytes32 suppliedHash, bytes32 matchHash);
  error M_NotWhitelisted();
  error M_NotOwnerAddress(address sender, address owner);
  error M_AccountFrozen(address owner);
  error M_CannotTradeToSelf(uint accountId);
  error M_InsufficientFillAmount(uint orderNumber, uint remainingFill, uint requestedFill);
  error M_OrderExpired(uint blockTimestamp, uint expirationTime);
  error M_ZeroAmountToTrade();
  error M_TradingSameSide();
  error M_ArrayLengthMismatch(uint length1, uint length2, uint length3);
  error M_AskPriceBelowLimit(uint limitPrice, uint calculatedPrice);
  error M_BidPriceAboveLimit(uint limitPrice, uint calculatedPrice);
  error M_CannotTradeSameAsset(IAsset baseAsset, IAsset quoteAsset);
  error M_AccountIdsDoNotMatch(uint order1fromId, uint order2toId, uint order1toId, uint order2fromId);
  error M_TradeFeeExceedsMaxFee(uint tradeFee, uint maxFee);
}
