//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.13;
//
//import "openzeppelin/utils/math/SafeCast.sol";
//import "openzeppelin/utils/cryptography/EIP712.sol";
//import "openzeppelin/utils/cryptography/SignatureChecker.sol";
//import "openzeppelin/access/Ownable2Step.sol";
//import "lyra-utils/decimals/DecimalMath.sol";
//import "lyra-utils/decimals/SignedDecimalMath.sol";
//
//import "v2-core/interfaces/ICashAsset.sol";
//import "v2-core/interfaces/ISubAccounts.sol";
//import "v2-core/interfaces/IPerpAsset.sol";
//
//import "forge-std/console2.sol";
//
///**
// * @title Matching
// * @author Lyra
// * @notice Matching contract that allows whitelisted addresses to submit trades for accounts.
// */
//contract Old_Matching is EIP712, Ownable2Step {
//  using DecimalMath for uint;
//  using SignedDecimalMath for int;
//  using SafeCast for uint;
//
//  ///@dev Account Id which receives all fees paid
//  uint public feeAccountId;
//
//  ///@dev Cooldown seconds a user must wait before withdrawing their account
//  uint public withdrawAccountCooldownParam;
//
//  ///@dev Cooldown seconds a user must wait before withdrawing their cash
//  uint public withdrawCashCooldownParam;
//
//  ///@dev Cooldown seconds a user must wait before deregister
//  uint public deregisterKeyCooldownParam;
//
//  ///@dev Accounts contract address
//  ISubAccounts public immutable accounts;
//
//  ///@dev The cash asset used as quote and for paying fees
//  address public cashAsset;
//
//  ///@dev The perp asset
//  IPerpAsset public perpAsset;
//
//  ///@dev Mapping of (address => isWhitelistedModule)
//  mapping(address => bool) public isWhitelisted;
//
//  ///@dev Mapping of accountId to address
//  mapping(uint => address) public accountToOwner;
//
//  ///@dev Mapping of signer address -> owner address -> expiry
//  mapping(address => mapping(address => uint)) public sessionKeys; // Allows other addresses to trade on behalf of others
//
//  ///@dev Mapping to track fill amounts and fee total per order
//  mapping(bytes32 => OrderFills) public fillAmounts;
//
//  ///@dev Mapping of owner to account withdraw cooldown start time
//  mapping(address => uint) public withdrawAccountCooldownMapping;
//
//  ///@dev Mapping of owner to signal cash cooldown start time
//  mapping(address => uint) public withdrawCashCooldownMapping;
//
//  ///@dev Mapping of accountId -> nonce -> used
//  mapping(uint => mapping(uint => bool)) public nonceUsed;
//
//  ///@dev Order fill typehash containing the limit order hash and trading pair hash, exluding the counterparty for the trade (accountId2)
//  bytes32 public constant _LIMITORDER_TYPEHASH =
//    keccak256("LimitOrder(bool,uint256,uint256,uint256,uint256,uint256,uint256,bytes32)");
//
//  ///@dev Transfer Asset typehash containing the asset and amount you want to transfer
//  bytes32 public constant _TRANSFER_ASSET_TYPEHASH = keccak256("TransferAsset(uint256,uint256,uint256,bytes32");
//
//  ///@dev Mint account typehash containing desired owner address, manager and expiry of the signing address
//  bytes32 public constant _MINT_ACCOUNT_TYPEHASH = keccak256("MintAccount(address,address");
//
//  ///@dev Instrument typehash containing the two IAssets and subIds
//  bytes32 public constant _INSTRUMENT_TYPEHASH = keccak256("address,address,uint256,uint256");
//
//  ///@dev Asset typehash containing the IAsset and subId
//  bytes32 public constant _ASSET_TYPEHASH = keccak256("address,uint256");
//
//  constructor(ISubAccounts _accounts, address _cashAsset, uint _feeAccountId) EIP712("Matching", "1.0") {
//    accounts = _accounts;
//    cashAsset = _cashAsset;
//    feeAccountId = _feeAccountId;
//  }
//
//  /**
//   * @notice Allows whitelisted addresses to force close an account with no cooldown delay.
//   */
//  function forceCloseCLOBAccount(uint accountId) external onlyWhitelisted {
//    accounts.transferFrom(address(this), accountToOwner[accountId], accountId);
//    delete accountToOwner[accountId];
//
//    emit ClosedCLOBAccount(accountId);
//  }
//
//  //////////////////////////
//  //  External Functions  //
//  //////////////////////////
//
//  ///////////////////////
//  //  Account actions  //
//  ///////////////////////
//  /**
//   * @notice Allows user to open an account by transferring their account NFT to this contract.
//   * @dev User must approve contract first.
//   * @param accountId The users' accountId
//   */
//  function openCLOBAccount(uint accountId) external {
//    accounts.transferFrom(msg.sender, address(this), accountId);
//    accountToOwner[accountId] = msg.sender;
//
//    emit OpenedCLOBAccount(accountId);
//  }
//
//  /**
//   * @notice Allows signature to create new subAccount, open a CLOB account, and transfer asset.
//   * @dev Signature should have signed the transfer.
//   */
//  function mintAccountAndTransfer(
//    MintAccount memory newAccount,
//    TransferAsset memory transfer,
//    IAsset asset,
//    uint subId,
//    bytes memory signature
//  ) external returns (uint newId) {
//    address toAllow = _recoverAddress(_getTransferHash(transfer), signature);
//    newId = _mintCLOBAccount(newAccount, toAllow);
//
//    ISubAccounts.AssetTransfer memory assetTransfer = _verifyTransferAsset(transfer, asset, subId, newId, signature);
//    accounts.submitTransfer(assetTransfer, "");
//
//    emit OpenedCLOBAccount(newId);
//  }
//
//  /**
//   * @notice Activates the cooldown period to withdraw account.
//   */
//  function requestCloseCLOBAccount(uint accountId) external {
//    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
//    withdrawAccountCooldownMapping[msg.sender] = block.timestamp;
//    emit AccountCooldown(msg.sender);
//  }
//
//  /**
//   * @notice Allows user to close their account by transferring their account NFT back.
//   * @dev User must have previously called `requestCloseCLOBAccount()` and waited for the cooldown to elapse.
//   * @param accountId The users' accountId
//   */
//  function completeCloseCLOBAccount(uint accountId) external {
//    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
//    if (withdrawAccountCooldownMapping[msg.sender] + (withdrawAccountCooldownParam) > block.timestamp) {
//      revert M_CooldownNotElapsed(
//        withdrawAccountCooldownMapping[msg.sender] + (withdrawAccountCooldownParam) - block.timestamp
//      );
//    }
//
//    accounts.transferFrom(address(this), msg.sender, accountId);
//    withdrawAccountCooldownMapping[msg.sender] = 0;
//    delete accountToOwner[accountId];
//
//    emit ClosedCLOBAccount(accountId);
//  }
//
//  ////////////////////
//  //  Session Keys  //
//  ////////////////////
//
//  /**
//   * @notice Allows owner to register the public address associated with their session key to their accountId.
//   * @dev Registered address gains owner address permission to the subAccount until expiry.
//   * @param expiry When the access to the owner address expires
//   */
//  function registerSessionKey(address toAllow, uint expiry) external {
//    sessionKeys[toAllow][msg.sender] = expiry;
//
//    emit SessionKeyRegistered(msg.sender, toAllow);
//  }
//
//  /**
//   * @notice Allows owner to deregister a session key from their account.
//   * @dev Expires the sessionKey after the cooldown.
//   */
//  function requestDeregisterSessionKey(address sessionKey) external {
//    // Ensure the session key has not expired
//    if (sessionKeys[sessionKey][msg.sender] < block.timestamp) revert M_SessionKeyInvalid(sessionKey);
//
//    sessionKeys[sessionKey][msg.sender] = block.timestamp + deregisterKeyCooldownParam;
//    emit SessionKeyCooldown(msg.sender, sessionKey);
//  }
//
//  /////////////////////
//  //  Withdraw Cash  //
//  /////////////////////
//
//  /**
//   * @notice Activates the cooldown period to withdraw cash.
//   */
//  function requestWithdrawCash(uint accountId) external {
//    if (accountToOwner[accountId] != msg.sender) revert M_NotOwnerAddress(msg.sender, accountToOwner[accountId]);
//    withdrawCashCooldownMapping[msg.sender] = block.timestamp;
//    emit CashCooldown(msg.sender);
//  }
//
//  /**
//   * @notice Withdraw cash from an accountId using a signature.
//   * @dev Owner address must have requested for withdrawal first and waited for the cooldown to elapse.
//   */
//  function completeWithdrawCash(TransferAsset memory transfer, bytes memory signature) external {
//    if (withdrawCashCooldownMapping[accountToOwner[transfer.fromAcc]] + (withdrawCashCooldownParam) > block.timestamp) {
//      revert M_CooldownNotElapsed(
//        withdrawCashCooldownMapping[accountToOwner[transfer.fromAcc]] + (withdrawCashCooldownParam) - block.timestamp
//      );
//    }
//    // Verify signatures
//    bytes32 transferHash = _getTransferHash(transfer);
//    if (!_verifySignature(transfer.fromAcc, transferHash, signature)) {
//      revert M_InvalidSignature(accountToOwner[transfer.fromAcc]);
//    }
//
//    ICashAsset(cashAsset).withdraw(transfer.fromAcc, transfer.amount, accountToOwner[transfer.fromAcc]);
//  }
//
//  //////////////////////////
//  //  Internal Functions  //
//  //////////////////////////
//
//  /**
//   * @dev Mints a new CLOB Account by creating a subAccount
//   * @param newAccount the details of the new account to be minted. The MintAccount struct contains the owner of the new account and the manager of the new account.
//   * @param toAllow is the address to be allowed for executing functions on behalf of the account owner
//   * @return newId returns the newly created account ID
//   */
//  function _mintCLOBAccount(MintAccount memory newAccount, address toAllow) internal returns (uint newId) {
//    if (sessionKeys[toAllow][newAccount.owner] < block.timestamp) revert M_SessionKeyInvalid(toAllow);
//    newId = accounts.createAccount(address(this), IManager(newAccount.manager));
//    accountToOwner[newId] = newAccount.owner;
//  }
//
//  function _isPerpTrade(address baseAsset, address quoteAsset) internal view returns (bool) {
//    if (baseAsset == address(perpAsset) && quoteAsset == address(0)) return true;
//    return false;
//  }
//
//  /**
//   * @notice Verify signature against owner address or permissioned address.
//   */
//  function _verifySignature(uint accountId, bytes32 structuredHash, bytes memory signature)
//    internal
//    view
//    returns (bool)
//  {
//    if (
//      SignatureChecker.isValidSignatureNow(accountToOwner[accountId], _hashTypedDataV4(structuredHash), signature)
//        == true
//    ) {
//      return true;
//    } else {
//      address signer = _recoverAddress(structuredHash, signature);
//      if (sessionKeys[signer][accountToOwner[accountId]] > block.timestamp) {
//        return true;
//      }
//      return false;
//    }
//  }
//
//  function _verifyNonceForOrder(uint accountId, uint nonce) internal view {
//    // If the nonce is used revert
//    if (nonceUsed[accountId][nonce]) revert M_NonceUsed(accountId, nonce);
//  }
//
//  /////////////////////////
//  //  Hashing Functions  //
//  /////////////////////////
//
//  function _getInstrumentHash(IAsset baseAsset, IAsset quoteAsset, uint baseSubId, uint quoteSubId)
//    internal
//    pure
//    returns (bytes32)
//  {
//    return keccak256(abi.encode(_INSTRUMENT_TYPEHASH, baseAsset, quoteAsset, baseSubId, quoteSubId));
//  }
//
//  function _getOrderHash(LimitOrder memory order) internal pure returns (bytes32) {
//    return keccak256(
//      abi.encode(
//        _LIMITORDER_TYPEHASH,
//        order.isBid,
//        order.accountId1,
//        order.amount,
//        order.limitPrice,
//        order.expirationTime,
//        order.maxFee,
//        order.nonce,
//        order.instrumentHash
//      )
//    );
//  }
//
//  function _getTransferHash(TransferAsset memory transfer) internal pure returns (bytes32) {
//    return keccak256(
//      abi.encode(_TRANSFER_ASSET_TYPEHASH, transfer.amount, transfer.fromAcc, transfer.toAcc, transfer.assetHash)
//    );
//  }
//
//  function _getTransferManyAssetsHash(TransferManyAssets memory transferMany) internal pure returns (bytes32) {
//    bytes memory buffer;
//
//    for (uint i = 0; i < transferMany.assets.length; i++) {
//      bytes32 assetHash = _getTransferHash(transferMany.assets[i]);
//      buffer = abi.encodePacked(buffer, assetHash);
//    }
//
//    return keccak256(buffer);
//  }
//
//  function _getAssetHash(IAsset asset, uint subId) internal pure returns (bytes32) {
//    return keccak256(abi.encode(_ASSET_TYPEHASH, address(asset), subId));
//  }
//
//  function _recoverAddress(bytes32 hash, bytes memory signature) internal view returns (address) {
//    (address recovered,) = ECDSA.tryRecover(_hashTypedDataV4(hash), signature);
//    return recovered;
//  }
//
//  ///////////
//  // Views //
//  ///////////
//
//  /**
//   * @dev get domain separator for signing
//   */
//  function domainSeparator() external view returns (bytes32) {
//    return _domainSeparatorV4();
//  }
//
//  function getOrderHash(LimitOrder calldata order) external pure returns (bytes32) {
//    return _getOrderHash(order);
//  }
//
//  function getTransferHash(TransferAsset calldata transfer) external pure returns (bytes32) {
//    return _getTransferHash(transfer);
//  }
//
//  function getAssetHash(IAsset asset, uint subId) external pure returns (bytes32) {
//    return _getAssetHash(asset, subId);
//  }
//
//  function getInstrument(IAsset baseAsset, IAsset quoteAsset, uint baseSubId, uint quoteSubId)
//    external
//    pure
//    returns (bytes32)
//  {
//    return _getInstrumentHash(baseAsset, quoteAsset, baseSubId, quoteSubId);
//  }
//
//  function verifySignature(uint accountId, bytes32 orderHash, bytes memory signature) external view returns (bool) {
//    return _verifySignature(accountId, orderHash, signature);
//  }
//
//  /////////////////
//  //  Modifiers  //
//  /////////////////
//
//  modifier onlyWhitelisted() {
//    if (!isWhitelisted[msg.sender]) revert M_NotWhitelisted();
//    _;
//  }
//}
