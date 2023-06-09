// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "v2-core/src/SubAccounts.sol";
import "./interfaces/IMatcher.sol";
import "./SubAccountsManager.sol";
import "./Matching.sol";

// todo naming
// todo functions for verifying and hashing structs
contract HashingLogic is EIP712, IMatcher, Ownable2Step {
  Matching public matching;

  /**
   * @notice Set Matching contract
   */
  function setMatching(Matching _matching) external onlyOwner {
    matching = _matching;

    emit MatchingSet(address(_matching));
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
      if (matching.sessionKeys[signer][accountToOwner[accountId]] > block.timestamp) {
        return true;
      }
      return false;
    }
  }
}
