// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "./BaseTSA.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";
import "openzeppelin/utils/cryptography/MessageHashUtils.sol";

/// @title BaseOnChainSigningTSA
/// @dev Prices shares in USD, but accepts baseAsset as deposit. Vault intended to try remain delta neutral.
abstract contract BaseOnChainSigningTSA is BaseTSA {
  // bytes4(keccak256("isValidSignature(bytes32,bytes)")
  bytes4 internal constant MAGICVALUE = 0x1626ba7e;

  /// @custom:storage-location erc7201:lyra.storage.BaseOnChainSigningTSA
  struct BaseSigningTSAStorage {
    bool signaturesDisabled;
    mapping(address => bool) signers;
    mapping(bytes32 => bool) signedData;
    /// @dev Submitters are allowed to submit actions on behalf of the TSA, only with a signature from a signer
    mapping(address => bool) submitters;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.BaseOnChainSigningTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant BaseSigningTSAStorageLocation =
    0x9f245ffe322048fbfccbbec5cbd54060b7369b5a75ba744e76b5291974322100;

  function _getBaseSigningTSAStorage() private pure returns (BaseSigningTSAStorage storage $) {
    assembly {
      $.slot := BaseSigningTSAStorageLocation
    }
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

  function setSubmitter(address submitter, bool _isSubmitter) external onlyOwner {
    _getBaseSigningTSAStorage().submitters[submitter] = _isSubmitter;

    emit SubmitterUpdated(submitter, _isSubmitter);
  }

  /////////////
  // Signing //
  /////////////

  function signActionData(IMatching.Action memory action, bytes memory extraData) external virtual onlySigner {
    _signActionData(action, extraData);
  }

  function signActionViaPermit(IMatching.Action memory action, bytes memory extraData, bytes memory signerSig)
    external
    virtual
    onlySubmitters
  {
    bytes32 hash = getActionTypedDataHash(action);

    (address recovered, ECDSA.RecoverError error, ) = ECDSA.tryRecover(hash, signerSig);
    require(error == ECDSA.RecoverError.NoError && _getBaseSigningTSAStorage().signers[recovered], "Invalid signature");

    // require signerSig is a valid signature of signer on hash
    _signActionData(action, extraData);
  }

  function _signActionData(IMatching.Action memory action, bytes memory extraData) internal {
    bytes32 hash = getActionTypedDataHash(action);

    if (action.signer != address(this)) {
      revert BOCST_InvalidAction();
    }
    _verifyAction(action, hash, extraData);
    _getBaseSigningTSAStorage().signedData[hash] = true;

    emit ActionSigned(action.signer, hash, action);
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

    return MessageHashUtils.toTypedDataHash(tsaAddresses.matching.domainSeparator(), tsaAddresses.matching.getActionHash(action));
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

  function isSubmitter(address submitter) external view returns (bool) {
    return _getBaseSigningTSAStorage().submitters[submitter];
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

  modifier onlySubmitters() {
    if (!_getBaseSigningTSAStorage().submitters[msg.sender]) {
      revert BOCST_OnlySubmitter();
    }
    _;
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event SignerUpdated(address indexed signer, bool isSigner);
  event SubmitterUpdated(address indexed submitter, bool isSubmitter);
  event SignaturesDisabledUpdated(bool enabled);

  event ActionSigned(address indexed signer, bytes32 indexed hash, IMatching.Action action);
  event SignatureRevoked(address indexed signer, bytes32 indexed hash);

  error BOCST_InvalidAction();
  error BOCST_OnlySigner();
  error BOCST_OnlySubmitter();
}
