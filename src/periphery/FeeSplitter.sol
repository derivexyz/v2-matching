pragma solidity ^0.8.18;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import "v2-core/src/interfaces/ISubAccounts.sol";

contract FeeSplitter is Ownable2Step {
  ISubAccounts public immutable subAccounts;
  uint public immutable subAcc;

  constructor(ISubAccounts _subAccounts, IManager manager) {
    subAccounts = _subAccounts;
    subAcc = _subAccounts.createAccount(address(this), manager);
  }

  ///////////
  // Admin //
  ///////////

  function setSplit(uint splitPercent) external onlyOwner {}

  function setSubAccounts(uint accountA, uint accountB) external onlyOwner {}

  //////////////
  // External //
  //////////////
  /// @notice Work out the balance of the subaccount held by this contract, and split it based on the % split
  function split() external {}
}