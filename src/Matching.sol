// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "v2-core/lib/lyra-utils/ownership/Owned.sol";
import "v2-core/lib/lyra-utils/decimals/DecimalMath.sol";


import "v2-core/interfaces/IAccounts.sol";
import "v2-core/interfaces/AccountStructs.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";

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
    bytes signature1;
    bytes signature2;
  }

  struct LimitOrder {
    uint accountId1; // todo rename to from Id <-> to Id ?
    uint accountId2;
    IAsset asset1;
    IAsset asset2; // todo for perps this asset is actually the price?
    uint subId1;
    uint subId2;
    uint asset1Amount;
    uint minPrice;
    uint expirationTime;
    uint orderId; // todo
  }

  // todo think about fees

  struct VerifiedOrder {
    uint accountId1;
    uint accountId2;
    IAsset asset1;
    IAsset asset2;
    uint subId1;
    uint subId2;
    uint asset1Amount;
    uint asset2Amount;
  }

  ///@dev Accounts contract address
  IAccounts public immutable accounts;

  ///@dev Mapping of (address => isWhitelistedModule)
  mapping(address => bool) public isWhitelisted;

  ///@dev Mapping of accountId to address
  mapping(uint => address) public accountToOwner;

  ///@dev Mapping to track fill amounts per order
  mapping(bytes32 => uint) public fillAmounts;

  ///@dev Mapping to track frozen accounts
  mapping(address => bool) public isFrozen;

  ///@dev LimitOrder Typehash including fillAmount
  bytes32 public constant _LIMIT_ORDER_TYPEHASH =
    keccak256("LimitOrder(uint256,uint256,address,uint256,address,uint256,uint256,uint256,uint256,uint256,uint256)");

  constructor(IAccounts _accounts) EIP712("Matching", "1.0") {
    accounts = _accounts;
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

  /**
   * @notice Allows sender to 'freeze' their account which blocks all trading actions.
   * @param freeze Boolean on whether to freeze or unfreeze your account
   */
  function freezeAccount(bool freeze) external {
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
  function _trade(Match calldata matchDetails, LimitOrder calldata order1, LimitOrder calldata order2)
    internal
    returns (VerifiedOrder memory matchedOrder)
  {
    // Verify signatures
    if (!_verifySignature(order1, matchDetails.amount1, matchDetails.signature1)) {
      revert M_InvalidSignature(accountToOwner[order1.accountId1]);
    }
    if (!_verifySignature(order2, matchDetails.amount2, matchDetails.signature2)) {
      revert M_InvalidSignature(accountToOwner[order2.accountId1]);
    }

    // Verify order details
    _verifyOrderParams(order1);
    _verifyOrderParams(order2);

    // todo ensure the assets are being traded for each other

    // Verify price and match details
    _verifyOrderMatch(order1, order2, matchDetails);

    // Get the order hashes
    bytes32 orderHash1 = _getOrderHash(order1, matchDetails.amount1);
    bytes32 orderHash2 = _getOrderHash(order2, matchDetails.amount2);
    console.log("Order2: ", uint(orderHash2));

    // Ensure the orders have not been completely filled yet
    uint remainingAmount1 = order1.asset1Amount - fillAmounts[orderHash1];
    uint remainingAmount2 = order2.asset1Amount - fillAmounts[orderHash2];
    console.log("remainingAmount2", remainingAmount2);
    console.log("matchdetailsAmot", matchDetails.amount2);
    console.log("fillAmountOrder2", fillAmounts[orderHash2]);
    // todo can update to fill as much as possible ?
    if (remainingAmount1 < matchDetails.amount1) {
      revert M_InsufficientFillAmount(1, remainingAmount1, matchDetails.amount1);
    }
    if (remainingAmount2 < matchDetails.amount2) {
      revert M_InsufficientFillAmount(2, remainingAmount2, matchDetails.amount2);
    }

    // Update the filled amounts for the orders
    fillAmounts[orderHash1] += matchDetails.amount1;
    fillAmounts[orderHash2] += matchDetails.amount2;

    return VerifiedOrder({
      accountId1: order1.accountId1,
      accountId2: order1.accountId2,
      asset1: order1.asset1,
      asset2: order1.asset2,
      subId1: order1.subId1,
      subId2: order1.subId2,
      asset1Amount: matchDetails.amount1,
      asset2Amount: matchDetails.amount2
    });
  }

  function _verifyOrderParams(LimitOrder calldata order) internal view {
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

  function _verifyOrderMatch(LimitOrder memory order1, LimitOrder memory order2, Match memory matchDetails)
    internal
    view
  {
    if (matchDetails.amount1 == 0 && matchDetails.amount1 == matchDetails.amount2) revert M_ZeroAmountToTrade();
    if (order1.accountId1 != order2.accountId2 || order1.accountId2 != order2.accountId1) {
      revert M_AccountIdsDoNotMatch(order1.accountId1, order2.accountId2, order1.accountId2, order2.accountId1);
    }
    uint calculatedPrice = matchDetails.amount1.divideDecimal(matchDetails.amount2);

    console.log("Order 1 amount:", order1.asset1Amount);
    console.log("Order 2 amount:", order2.asset1Amount);
    console.log("Order 1 min price:", order1.minPrice);
    console.log("Order 2 min price:", order2.minPrice);
    console.log("Executed price   :", calculatedPrice);

    // Verify the calculated price is greater or equal to min price for both orders
    if (calculatedPrice < order1.minPrice) revert M_PriceBelowMinPrice(order1.minPrice, calculatedPrice);
    if (calculatedPrice < order2.minPrice) revert M_PriceBelowMinPrice(order2.minPrice, calculatedPrice);

    // Verify that the two assets are being traded for each other
    if (order1.asset1 != order2.asset2 || order1.asset2 != order2.asset1) {
      revert M_TradingDifferentAssets(order1.asset1, order2.asset2, order1.asset2, order1.asset1);
    } else if (order1.subId1 != order2.subId2 || order1.subId2 != order2.subId1) {
      revert M_TradingDifferentSubIds(order1.subId1, order2.subId2, order1.subId2, order1.subId1);
    }
  }

  function _submitAssetTransfers(VerifiedOrder[] memory orders) internal {
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](orders.length * 2);

    for (uint i = 0; i < orders.length; i++) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: orders[i].accountId1,
        toAcc: orders[i].accountId2,
        asset: orders[i].asset1,
        subId: orders[i].subId1,
        amount: orders[i].asset1Amount.toInt256(),
        assetData: bytes32(0)
      });

      transferBatch[i + 1] = AccountStructs.AssetTransfer({
        fromAcc: orders[i].accountId2,
        toAcc: orders[i].accountId1,
        asset: orders[i].asset2,
        subId: orders[i].subId2,
        amount: orders[i].asset2Amount.toInt256(),
        assetData: bytes32(0)
      });
    }

    accounts.submitTransfers(transferBatch, "");
  }

  function _verifySignature(LimitOrder calldata order, uint fillAmount, bytes calldata signature)
    internal
    view
    returns (bool)
  {
    bytes32 orderHash = _getOrderHash(order, fillAmount);
    return
      SignatureChecker.isValidSignatureNow(accountToOwner[order.accountId1], _hashTypedDataV4(orderHash), signature);
  }

  function _getOrderHash(LimitOrder calldata order, uint fillAmount) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(
        _LIMIT_ORDER_TYPEHASH,
        order.accountId1,
        order.accountId2,
        order.asset1,
        order.subId1,
        order.asset2,
        order.subId2,
        order.asset1Amount,
        order.minPrice,
        order.expirationTime,
        order.orderId,
        fillAmount
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

  function getOrderHash(LimitOrder calldata order, uint fillAmount) external pure returns (bytes32) {
    return _getOrderHash(order, fillAmount);
  }

  function verifySignature(LimitOrder calldata order, uint fillAmount, bytes calldata signature)
    external
    view
    returns (bool)
  {
    return _verifySignature(order, fillAmount, signature);
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

  ////////////
  // Errors //
  ////////////

  error M_InvalidSignature(address signer);
  error M_NotWhitelisted();
  error M_NotOwnerAddress(address sender, address owner);
  error M_AccountFrozen(address owner);
  error M_CannotTradeToSelf(uint accountId);
  error M_InsufficientFillAmount(uint orderNumber, uint remainingFill, uint requestedFill);
  error M_OrderExpired(uint blockTimestamp, uint expirationTime);
  error M_ZeroAmountToTrade();
  error M_ArrayLengthMismatch(uint length1, uint length2, uint length3);
  error M_PriceBelowMinPrice(uint order1Price, uint order2Price);
  error M_TradingDifferentAssets(IAsset order1Asset1, IAsset order2Asset2, IAsset order1Asset2, IAsset order2Asset1);
  error M_TradingDifferentSubIds(uint order1SubId1, uint order2SubId2, uint order1SubId2, uint order2SubId1);
  error M_AccountIdsDoNotMatch(uint order1fromId, uint order2toId, uint order1toId, uint order2fromId);
}
