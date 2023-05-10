// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "lyra-utils/ownership/Owned.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "v2-core/src/Accounts.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";

// todo jit account, create new acount on trade and merge after
// todo sub signers
/**
 * @title Matching
 * @author Lyra
 * @notice Matching contract that allows whitelisted address to submit trades for accounts.
 */
contract Matching is EIP712, Owned {
  using DecimalMath for uint;
  using SafeCast for uint;

  struct Match {
    uint amount1;
    uint amount2;
    IAsset asset1;
    IAsset asset2;
    uint subId1;
    uint subId2;
    bytes signature1;
    bytes signature2;
  }

  // todo perp asset data
  struct LimitOrder {
    bool isBid;
    uint accountId1;
    uint accountId2;
    uint asset1Amount;
    uint limitPrice;
    uint expirationTime;
    uint maxFee;
    uint tradeFee;
    uint salt; // todo optional for users with duplicate orders
    bytes32 assetHash;
  }

  struct VerifiedOrder {
    uint accountId1;
    uint accountId2;
    IAsset asset1;
    IAsset asset2;
    uint subId1;
    uint subId2;
    uint asset1Amount;
    uint asset2Amount;
    uint accountId1Fee;
    uint accountId2Fee;
  }

  struct OrderHash {
    bool isBid;
    uint maker;
    uint asset1Amount;
    uint limitPrice;
    uint expirationTime;
    uint maxFee;
    uint salt;
    bytes32 assetHash;
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

  ///@dev LimitOrder typehash including fillAmount
  bytes32 public constant _ORDER_TYPEHASH =
    keccak256("OrderHash(bool,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256)");

  ///@dev Order fill typehash containing the order hash and asset hash (exlcuding fill amount)
  bytes32 public constant _ORDER_FILL_TYPEHASH =
    keccak256("OrderHash(bool,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256)");

  ///@dev Asset typehash containing the two IAssets and subIds
  bytes32 public constant _ASSET_TYPEHASH = keccak256("address,address,uint256,uint256");

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

  function submitTrade(Match calldata matchDetails, LimitOrder calldata order1, LimitOrder calldata order2)
    external
    onlyWhitelisted
    returns (VerifiedOrder memory matchedOrder)
  {
    return _trade(matchDetails, order1, order2);
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
    // Verify asset hashes
    bytes32 assetHash =
      _getAssetHash(matchDetails.asset1, matchDetails.asset2, matchDetails.subId1, matchDetails.subId2);
    if (order1.assetHash != assetHash) revert M_InvalidAssetHash(order1.assetHash, assetHash);
    if (order2.assetHash != assetHash) revert M_InvalidAssetHash(order2.assetHash, assetHash);

    OrderHash memory order1Hash = OrderHash({
      isBid: order1.isBid,
      maker: order1.accountId1,
      asset1Amount: order1.asset1Amount,
      limitPrice: order1.limitPrice,
      expirationTime: order1.expirationTime,
      maxFee: order1.maxFee,
      salt: order1.salt,
      assetHash: order1.assetHash
    });

    OrderHash memory order2Hash = OrderHash({
      isBid: order2.isBid,
      maker: order2.accountId1,
      asset1Amount: order2.asset1Amount,
      limitPrice: order2.limitPrice,
      expirationTime: order2.expirationTime,
      maxFee: order1.maxFee,
      salt: order2.salt,
      assetHash: order1.assetHash
    });

    // Verify signatures
    if (!_verifySignature(order1Hash, matchDetails.amount1, assetHash, matchDetails.signature1)) {
      revert M_InvalidSignature(accountToOwner[order1.accountId1]);
    }
    if (!_verifySignature(order2Hash, matchDetails.amount2, assetHash, matchDetails.signature2)) {
      revert M_InvalidSignature(accountToOwner[order2.accountId1]);
    }

    // Verify both orders and the match
    _verifyOrderMatch(order1, order2, matchDetails);

    // Get the order hashes
    bytes32 orderFillHash1 = _getOrderFillHash(order1Hash, assetHash);
    bytes32 orderFillHash2 = _getOrderFillHash(order2Hash, assetHash);

    // Ensure the orders have not been completely filled yet
    uint remainingAmount1 = order1.asset1Amount - fillAmounts[orderFillHash1];
    uint remainingAmount2 = order2.asset1Amount - fillAmounts[orderFillHash2];

    if (remainingAmount1 < matchDetails.amount1) {
      revert M_InsufficientFillAmount(1, remainingAmount1, matchDetails.amount1);
    }
    if (remainingAmount2 < matchDetails.amount2) {
      revert M_InsufficientFillAmount(2, remainingAmount2, matchDetails.amount2);
    }

    // Update the filled amounts for the orders
    fillAmounts[orderFillHash1] += matchDetails.amount1;
    fillAmounts[orderFillHash2] += matchDetails.amount2;

    return VerifiedOrder({
      accountId1: order1.accountId1,
      accountId2: order1.accountId2,
      asset1: matchDetails.asset1,
      asset2: matchDetails.asset2,
      subId1: matchDetails.subId1,
      subId2: matchDetails.subId2,
      asset1Amount: matchDetails.amount1,
      asset2Amount: matchDetails.amount2,
      accountId1Fee: order1.tradeFee,
      accountId2Fee: order2.tradeFee
    });
  }

  function _verifyOrderMatch(LimitOrder memory order1, LimitOrder memory order2, Match memory matchDetails)
    internal
    view
  {
    // Verify individual order details
    _verifyOrderParams(order1);
    _verifyOrderParams(order2);

    // Check trade fee < maxFee
    if (order1.tradeFee > order1.maxFee) revert M_TradeFeeExceedsMaxFee(order1.tradeFee, order1.maxFee);
    if (order2.tradeFee > order2.maxFee) revert M_TradeFeeExceedsMaxFee(order2.tradeFee, order2.maxFee);

    // Check for zero trade amount
    if (matchDetails.amount1 == 0 && matchDetails.amount1 == matchDetails.amount2) revert M_ZeroAmountToTrade();

    // Ensure the trade is 1 to 1
    if (order1.accountId1 != order2.accountId2 || order1.accountId2 != order2.accountId1) {
      revert M_AccountIdsDoNotMatch(order1.accountId1, order2.accountId2, order1.accountId2, order2.accountId1);
    }

    // Verify the calculated price is within the limit price
    uint calculatedPrice = matchDetails.amount1.divideDecimal(matchDetails.amount2);
    _checkLimitPrice(order1.isBid, order1.limitPrice, calculatedPrice);
    _checkLimitPrice(order2.isBid, order2.limitPrice, calculatedPrice);

    // Verify that the two assets are being traded for each other
    if (matchDetails.asset1 != matchDetails.asset2 || matchDetails.asset2 != matchDetails.asset1) {
      revert M_TradingDifferentAssets(
        matchDetails.asset1, matchDetails.asset2, matchDetails.asset2, matchDetails.asset1
      );
    } else if (matchDetails.subId1 != matchDetails.subId2 || matchDetails.subId2 != matchDetails.subId1) {
      revert M_TradingDifferentSubIds(
        matchDetails.subId1, matchDetails.subId2, matchDetails.subId2, matchDetails.subId1
      );
    }
  }

  function _verifyOrderParams(LimitOrder memory order) internal view {
    // Ensure the maker and taker are different accounts
    if (order.accountId1 == order.accountId2) revert M_CannotTradeToSelf(order.accountId1);

    // Ensure the maker and taker accounts are not frozen
    if (isFrozen[accountToOwner[order.accountId1]]) revert M_AccountFrozen(accountToOwner[order.accountId1]);
    if (isFrozen[accountToOwner[order.accountId2]]) revert M_AccountFrozen(accountToOwner[order.accountId2]);

    // Ensure some amount is traded
    if (order.asset1Amount == 0) revert M_ZeroAmountToTrade();

    // Ensure order has not expired
    if (block.timestamp > order.expirationTime) revert M_OrderExpired(block.timestamp, order.expirationTime);
  }

  function _checkLimitPrice(bool isBid, uint limitPrice, uint calculatedPrice) internal pure {
    // If you want to buy but the price is above your limit
    if (isBid && calculatedPrice > limitPrice) {
      revert M_PriceAboveLimitPrice(limitPrice, calculatedPrice);
    } else if (!isBid && calculatedPrice < limitPrice) {
      // If you are selling but the price is below your limit
      revert M_PriceBelowLimitPrice(limitPrice, calculatedPrice);
    }
  }

  function _submitAssetTransfers(VerifiedOrder[] memory orders) internal {
    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](orders.length * 4);

    for (uint i = 0; i < orders.length; i++) {
      // Transfer assets between the two accounts
      transferBatch[i] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId1,
        toAcc: orders[i].accountId2,
        asset: orders[i].asset1,
        subId: orders[i].subId1,
        amount: orders[i].asset1Amount.toInt256(),
        assetData: bytes32(0)
      });

      transferBatch[i + 1] = IAccounts.AssetTransfer({
        fromAcc: orders[i].accountId2,
        toAcc: orders[i].accountId1,
        asset: orders[i].asset2,
        subId: orders[i].subId2,
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

  function _verifySignature(OrderHash memory order, uint fillAmount, bytes32 assetHash, bytes memory signature)
    internal
    view
    returns (bool)
  {
    bytes32 orderHash = _getFullOrderHash(order, assetHash, fillAmount);
    return SignatureChecker.isValidSignatureNow(accountToOwner[order.maker], _hashTypedDataV4(orderHash), signature);
  }

  function _getAssetHash(IAsset asset1, IAsset asset2, uint subId1, uint subId2) internal pure returns (bytes32) {
    return keccak256(abi.encode(_ASSET_TYPEHASH, asset1, asset2, subId1, subId2));
  }

  function _getFullOrderHash(OrderHash memory order, bytes32 assetHash, uint fillAmount)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(
      abi.encode(
        _ORDER_TYPEHASH,
        order.isBid,
        order.maker,
        order.asset1Amount,
        order.limitPrice,
        order.expirationTime,
        order.maxFee,
        order.salt,
        fillAmount,
        assetHash
      )
    );
  }

  function _getOrderFillHash(OrderHash memory order, bytes32 assetHash) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        _ORDER_FILL_TYPEHASH,
        order.isBid,
        order.maker,
        order.asset1Amount,
        order.limitPrice,
        order.expirationTime,
        order.maxFee,
        order.salt,
        assetHash
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

  function getFullOrderHash(OrderHash calldata order, bytes32 assetHash, uint fillAmount)
    external
    pure
    returns (bytes32)
  {
    return _getFullOrderHash(order, assetHash, fillAmount);
  }

  function getOrderFillHash(OrderHash calldata order, bytes32 assetHash) external pure returns (bytes32) {
    return _getOrderFillHash(order, assetHash);
  }

  function getAssetHash(IAsset asset1, IAsset asset2, uint subId1, uint subId2) external pure returns (bytes32) {
    return _getAssetHash(asset1, asset2, subId1, subId2);
  }

  function verifySignature(OrderHash calldata order, uint fillAmount, bytes32 assetHash, bytes calldata signature)
    external
    view
    returns (bool)
  {
    return _verifySignature(order, fillAmount, assetHash, signature);
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
  event Trade(bytes32 indexed orderHash, uint fillAmount);

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
  error M_InvalidAssetHash(bytes32 suppliedHash, bytes32 matchHash);
  error M_NotWhitelisted();
  error M_NotOwnerAddress(address sender, address owner);
  error M_AccountFrozen(address owner);
  error M_CannotTradeToSelf(uint accountId);
  error M_InsufficientFillAmount(uint orderNumber, uint remainingFill, uint requestedFill);
  error M_OrderExpired(uint blockTimestamp, uint expirationTime);
  error M_ZeroAmountToTrade();
  error M_ArrayLengthMismatch(uint length1, uint length2, uint length3);
  error M_PriceBelowLimitPrice(uint order1Price, uint order2Price);
  error M_PriceAboveLimitPrice(uint order1Price, uint order2Price);
  error M_TradingDifferentAssets(IAsset order1Asset1, IAsset order2Asset2, IAsset order1Asset2, IAsset order2Asset1);
  error M_TradingDifferentSubIds(uint order1SubId1, uint order2SubId2, uint order1SubId2, uint order2SubId1);
  error M_AccountIdsDoNotMatch(uint order1fromId, uint order2toId, uint order1toId, uint order2fromId);
  error M_TradeFeeExceedsMaxFee(uint tradeFee, uint maxFee);
}
