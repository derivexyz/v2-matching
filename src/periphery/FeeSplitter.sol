pragma solidity ^0.8.18;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

contract FeeSplitter is Ownable2Step {
  ISubAccounts public immutable subAccounts;
  uint public immutable subAcc;
  uint private splitPercent;
  uint private accountA;
  uint private accountB;

  constructor(ISubAccounts _subAccounts, IManager manager) {
    subAccounts = _subAccounts;
    subAcc = _subAccounts.createAccount(address(this), manager);
  }

  ///////////
  // Admin //
  ///////////

  function setSplit(uint splitPercent) external onlyOwner {
    require(_splitPercent <= 100, "Invalid percentage");
    splitPercent = _splitPercent;
  }

  function setSubAccounts(uint _accountA, uint _accountB) external onlyOwner {
    accountA = _accountA;
    accountB = _accountB;
  }

  //////////////
  // External //
  //////////////
  /// @notice Work out the balance of the subaccount held by this contract, and split it based on the % split
  function split() external {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(subAcc);

    for (uint i = 0; i < balances.length; i++) {
        IAsset asset = balances[i].asset;
        uint subId = balances[i].subId;
        int balance = balances[i].balance;

        if (balance > 0) {
            uint splitAmountA = uint(balance) * splitPercent / 100;
            uint splitAmountB = uint(balance) - splitAmountA;

            ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](2);
            transfers[0] = ISubAccounts.AssetTransfer({
                fromAcc: subAcc,
                toAcc: accountA,
                asset: asset,
                subId: subId,
                amount: int(splitAmountA),
                assetData: bytes32(0)
            });
            transfers[1] = ISubAccounts.AssetTransfer({
                fromAcc: subAcc,
                toAcc: accountB,
                asset: asset,
                subId: subId,
                amount: int(splitAmountB),
                assetData: bytes32(0)
            });

            subAccounts.submitTransfers(transfers, "");
        }
    }
  }
}