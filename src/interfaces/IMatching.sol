// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IAsset} from "v2-core/src/interfaces/IAsset.sol";

interface IMatching {
  struct Match {
    uint bidId;
    uint askId;
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
    uint nonce; // todo nonce, mapping nonce -> used
    bytes32 instrumentHash;
  }

  struct VerifiedTrade {
    uint bidId;
    uint askId;
    IAsset baseAsset;
    IAsset quoteAsset;
    uint baseSubId;
    uint quoteSubId;
    uint asset1Amount; // Position size for perps
    uint asset2Amount; // Delta paid for perps
    uint tradeFee;
    int perpDelta;
  }

  struct TransferAsset {
    uint amount;
    uint fromAcc;
    uint toAcc;
    bytes32 assetHash;
  }

  struct TransferManyAssets {
    TransferAsset[] assets;
  }

  struct MintAccount {
    address owner;
    address manager;
  }

  struct OrderFills {
    uint filledAmount;
    uint totalFees;
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
  error M_TradeSideAccountIdMisMatch(uint orderAccountId, uint matchAccountId);
  error M_NonceUsed(uint accountId, uint nonce);
}
