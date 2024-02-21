pragma solidity ^0.8.18;

import "lyra-utils/decimals/SignedDecimalMath.sol";

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts, IAsset} from "v2-core/src/interfaces/ISubAccounts.sol";

contract FeeSplitter is Ownable2Step {
  using SignedDecimalMath for int;

  ISubAccounts public immutable subAccounts;
  IAsset public immutable cashAsset;
  uint public immutable subAcc;

  uint public splitPercent;
  uint public accountA;
  uint public accountB;

  constructor(ISubAccounts _subAccounts, IManager manager, IAsset _cashAsset) {
    subAccounts = _subAccounts;
    subAcc = _subAccounts.createAccount(address(this), manager);
    cashAsset = _cashAsset;
  }

  ///////////
  // Admin //
  ///////////

  function setSplit(uint _splitPercent) external onlyOwner {
    if (_splitPercent > 1e18) {
      revert FS_InvalidSplitPercentage();
    }
    splitPercent = _splitPercent;
  }

  function setSubAccounts(uint _accountA, uint _accountB) external onlyOwner {
    accountA = _accountA;
    accountB = _accountB;
  }

  function recoverSubAccount(address recipient) external onlyOwner {
    subAccounts.transferFrom(address(this), recipient, subAcc);
  }

  //////////////
  // External //
  //////////////
  /// @notice Work out the balance of the subaccount held by this contract, and split it based on the % split
  function split() external {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(subAcc);

    for (uint i = 0; i < balances.length; i++) {
      IAsset asset = balances[i].asset;

      if (asset != cashAsset) {
        continue;
      }

      int balance = balances[i].balance;

      if (balance <= 0) {
        return;
      }

      int splitAmountA = balance.multiplyDecimal(int(splitPercent));
      int splitAmountB = balance - splitAmountA;

      ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](2);
      transfers[0] = ISubAccounts.AssetTransfer({
        fromAcc: subAcc,
        toAcc: accountA,
        asset: cashAsset,
        subId: 0,
        amount: int(splitAmountA),
        assetData: bytes32(0)
      });
      transfers[1] = ISubAccounts.AssetTransfer({
        fromAcc: subAcc,
        toAcc: accountB,
        asset: cashAsset,
        subId: 0,
        amount: int(splitAmountB),
        assetData: bytes32(0)
      });

      subAccounts.submitTransfers(transfers, "");
    }
  }

  ////////////
  // Errors //
  ////////////
  error FS_InvalidSplitPercentage();
}
