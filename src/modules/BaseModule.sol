// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Inherited
import {IBaseModule} from "../interfaces/IBaseModule.sol";

// Interfaces
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

abstract contract BaseModule is IBaseModule, Ownable2Step {
  IMatching public immutable matching;
  ISubAccounts public immutable subAccounts;

  mapping(address owner => mapping(uint nonce => bool used)) public usedNonces;

  constructor(IMatching _matching) {
    matching = _matching;
    subAccounts = _matching.subAccounts();
  }

  /**
   * @dev This contract should never hold any funds, but just in case, allow the owner to withdraw
   */
  function withdrawERC20(address token, address recipient, uint amount) external onlyOwner {
    IERC20(token).transfer(recipient, amount);
  }

  function _returnAccounts(VerifiedAction[] memory actions, uint[] memory newAccIds) internal {
    for (uint i = 0; i < actions.length; ++i) {
      if (actions[i].subaccountId == 0) continue;
      if (subAccounts.ownerOf(actions[i].subaccountId) == address(matching)) continue;

      subAccounts.transferFrom(address(this), address(matching), actions[i].subaccountId);
    }
    for (uint i = 0; i < newAccIds.length; ++i) {
      subAccounts.transferFrom(address(this), address(matching), newAccIds[i]);
    }
  }

  function _checkAndInvalidateNonce(address owner, uint nonce) internal {
    if (usedNonces[owner][nonce]) revert BM_NonceAlreadyUsed();
    usedNonces[owner][nonce] = true;

    emit NonceUsed(owner, nonce);
  }

  ///////////////
  // Modifiers //
  ///////////////
  modifier onlyMatching() {
    if (msg.sender != address(matching)) revert BM_OnlyMatching();
    _;
  }
}
