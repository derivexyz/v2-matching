// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
import {Black76} from "lyra-utils/math/Black76.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "lyra-utils/decimals/SignedDecimalMath.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import "./BaseTSA.sol";
import "../interfaces/IRfqModule.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import {ITradeModule} from "../interfaces/ITradeModule.sol";

/// @title BaseOnChainSigningTSA
/// @dev Prices shares in USD, but accepts baseAsset as deposit. Vault intended to try remain delta neutral.
abstract contract BaseOnChainSigningTSA is BaseTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  // bytes4(keccak256("isValidSignature(bytes32,bytes)")
  bytes4 internal constant MAGICVALUE = 0x1626ba7e;

  // TODO: Move this to composition
  // leaving this as is. Could definitely change later on.
  // initially attempted with a separate struct, but I dont like how it exposes new variables + new functions
  struct BaseSigningParams {
    /// @dev Percentage of spot that can be paid as a fee for both spot/options (e.g. 0.01e18)
    uint feeFactor;
    /// @dev A factor on how strict to be with preventing too much cash being used in swapping base asset (e.g. 1.01e18)
    int spotTransactionLeniency;
    /// @dev Percentage of spot price that the TSA will sell baseAsset at in the worst case (e.g. 0.98e18)
    uint worstSpotSellPrice;
    /// @dev Percentage of spot price that the TSA will sell baseAsset at in the worst case (e.g. 0.98e18)
    uint worstSpotBuyPrice;
  }

  /// @custom:storage-location erc7201:lyra.storage.BaseOnChainSigningTSA
  struct BaseSigningTSAStorage {
    bool signaturesDisabled;
    mapping(address => bool) signers;
    mapping(bytes32 => bool) signedData;
    BaseSigningParams baseParams;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.BaseOnChainSigningTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant BaseSigningTSAStorageLocation =
    0x9f245ffe322048fbfccbbec5cbd54060b7369b5a75ba744e76b5291974322100;

  function _getBaseSigningTSAStorage() internal pure returns (BaseSigningTSAStorage storage $) {
    assembly {
      $.slot := BaseSigningTSAStorageLocation
    }
  }

  function _setBaseParams(BaseSigningParams memory baseParams) internal onlyOwner {
    // some admin checks
    _getBaseSigningTSAStorage().baseParams = baseParams;
  }

  ///////////
  // Admin //
  ///////////
  function setSigner(address signer, bool _isSigner) external onlyOwner {
    _getBaseSigningTSAStorage().signers[signer] = _isSigner;

    emit SignerUpdated(signer, _isSigner);
  }

  function setSignaturesDisabled(bool disabled) external onlyOwner {
    _getBaseSigningTSAStorage().signaturesDisabled = disabled;

    emit SignaturesDisabledUpdated(disabled);
  }

  /////////////
  // Signing //
  /////////////

  function signActionData(IMatching.Action memory action, bytes memory extraData) external virtual onlySigner {
    bytes32 hash = getActionTypedDataHash(action);

    if (action.signer != address(this)) {
      revert BOCST_InvalidAction();
    }
    _verifyAction(action, hash, extraData);
    _getBaseSigningTSAStorage().signedData[hash] = true;

    emit ActionSigned(msg.sender, hash, action);
  }

  function revokeActionSignature(IMatching.Action memory action) external virtual onlySigner {
    _revokeSignature(getActionTypedDataHash(action));
  }

  function revokeSignature(bytes32 typedDataHash) external virtual onlySigner {
    _revokeSignature(typedDataHash);
  }

  function _revokeSignature(bytes32 hash) internal virtual {
    _getBaseSigningTSAStorage().signedData[hash] = false;

    emit SignatureRevoked(msg.sender, hash);
  }

  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory extraData) internal virtual;

  function getActionTypedDataHash(IMatching.Action memory action) public view returns (bytes32) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    return ECDSA.toTypedDataHash(tsaAddresses.matching.domainSeparator(), tsaAddresses.matching.getActionHash(action));
  }

  function _tradeCollateral(ITradeModule.TradeData memory tradeData) internal view {
    if (tradeData.isBid) {
      // Buying more collateral with excess cash
      _verifyCollateralBuy(tradeData);
    } else {
      // Selling collateral to cover cash debt
      _verifyCollateralSell(tradeData);
    }
  }

  // buying collateral will be through the trade module
  function _verifyCollateralBuy(ITradeModule.TradeData memory tradeData) internal view {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance <= 0) {
      revert BOCST_MustHavePositiveCash();
    }
    uint basePrice = _getBasePrice();

    // We don't worry too much about the fee in the calculations, as we trust the exchange won't cause issues. We make
    // sure max fee doesn't exceed 0.5% of spot though.
    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() > basePrice.multiplyDecimal($.baseParams.worstSpotBuyPrice)) {
      revert BOCST_SpotLimitPriceTooHigh();
    }

    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal($.baseParams.spotTransactionLeniency);
    if (cost > bufferedBalance) {
      revert BOCST_BuyingTooMuchCollateral();
    }
  }

  function _verifyCollateralSell(ITradeModule.TradeData memory tradeData) internal view {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    int cashBalance = tsaAddresses.subAccounts.getBalance(subAccount(), tsaAddresses.cash, 0);
    if (cashBalance >= 0) {
      revert BOCST_MustHaveNegativeCash();
    }

    uint basePrice = _getBasePrice();

    _verifyFee(tradeData.worstFee, basePrice);

    if (tradeData.limitPrice.toUint256() < basePrice.multiplyDecimal($.baseParams.worstSpotSellPrice)) {
      revert BOCST_SpotLimitPriceTooLow();
    }

    // cost is positive, balance is negative
    int cost = tradeData.limitPrice.multiplyDecimal(tradeData.desiredAmount);
    int bufferedBalance = cashBalance.multiplyDecimal($.baseParams.spotTransactionLeniency);

    // We make sure we're not selling more $ value of collateral than we have in debt
    if (cost.abs() > bufferedBalance.abs()) {
      revert BOCST_SellingTooMuchCollateral();
    }
  }

  function _getBasePrice() internal view virtual returns (uint);

  function _verifyFee(uint worstFee, uint basePrice) internal view {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    if (worstFee > basePrice.multiplyDecimal($.baseParams.feeFactor)) {
      revert BOCST_FeeTooHigh();
    }
  }

  ////////////////
  // Validation //
  ////////////////
  function isValidSignature(bytes32 _hash, bytes memory _signature)
    external
    view
    checkBlocked
    returns (bytes4 magicValue)
  {
    // contains hash of one particular action
    if (_isValidSignature(_hash, _signature)) {
      return MAGICVALUE;
    }
    return bytes4(0);
  }

  function _isValidSignature(bytes32 _hash, bytes memory /* _signature */ ) internal view virtual returns (bool) {
    BaseSigningTSAStorage storage $ = _getBaseSigningTSAStorage();

    return !$.signaturesDisabled && $.signedData[_hash];
  }

  ///////////
  // Views //
  ///////////
  function isSigner(address signer) external view returns (bool) {
    return _getBaseSigningTSAStorage().signers[signer];
  }

  function signaturesDisabled() external view returns (bool) {
    return _getBaseSigningTSAStorage().signaturesDisabled;
  }

  function signedData(bytes32 hash) public view returns (bool) {
    return _getBaseSigningTSAStorage().signedData[hash];
  }

  function isActionSigned(IMatching.Action memory action) external view returns (bool) {
    return signedData(getActionTypedDataHash(action));
  }

  ///////////////
  // Modifiers //
  ///////////////
  modifier onlySigner() {
    if (!_getBaseSigningTSAStorage().signers[msg.sender]) {
      revert BOCST_OnlySigner();
    }
    _;
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event SignerUpdated(address indexed signer, bool isSigner);
  event SignaturesDisabledUpdated(bool enabled);

  event ActionSigned(address indexed signer, bytes32 indexed hash, IMatching.Action action);
  event SignatureRevoked(address indexed signer, bytes32 indexed hash);

  error BOCST_InvalidAction();
  error BOCST_OnlySigner();
  error BOCST_InvalidDesiredAmount();
  error BOCST_InvalidAsset();
  error BOCST_MustHavePositiveCash();
  error BOCST_SpotLimitPriceTooHigh();
  error BOCST_BuyingTooMuchCollateral();
  error BOCST_SpotLimitPriceTooLow();
  error BOCST_SellingTooMuchCollateral();
  error BOCST_FeeTooHigh();
  error BOCST_MustHaveNegativeCash();
}
