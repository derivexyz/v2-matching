pragma solidity ^0.8.18;

import "lyra-utils/decimals/SignedDecimalMath.sol";

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ISubAccounts, IAsset} from "v2-core/src/interfaces/ISubAccounts.sol";

/**
 * @title FeeSplitter
 * @notice FeeSplitter is a contract that splits the balance of a subaccount held by this contract based on a % split
 * @author Lyra
 */
contract FeeSplitter is Ownable2Step {
  using SignedDecimalMath for int;

  ISubAccounts public immutable subAccounts;
  IAsset public immutable cashAsset;

  uint public subAcc;
  uint public splitPercent = 0.5e18;
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

  /// @notice Set the % split
  function setSplit(uint _splitPercent) external onlyOwner {
    if (_splitPercent > 1e18) {
      revert FS_InvalidSplitPercentage();
    }
    splitPercent = _splitPercent;

    emit SplitPercentSet(_splitPercent);
  }

  /// @notice Set the subaccounts to split the balance between
  function setSubAccounts(uint _accountA, uint _accountB) external onlyOwner {
    accountA = _accountA;
    accountB = _accountB;

    emit SubAccountsSet(_accountA, _accountB);
  }

  /// @notice Recover a subaccount held by this contract, creating a new one in its place
  function recoverSubAccount(address recipient) external onlyOwner {
    uint oldSubAcc = subAcc;
    subAccounts.transferFrom(address(this), recipient, oldSubAcc);
    subAcc = subAccounts.createAccount(address(this), subAccounts.manager(oldSubAcc));

    emit SubAccountRecovered(oldSubAcc, recipient, subAcc);
  }

  //////////////
  // External //
  //////////////
  /// @notice Work out the balance of the subaccount held by this contract, and split it based on the % split
  function split() external {
    int balance = subAccounts.getBalance(subAcc, cashAsset, 0);

    if (balance <= 0) {
      revert FS_NoBalanceToSplit();
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

    emit BalanceSplit(subAcc, accountA, accountB, splitAmountA, splitAmountB);
  }

  ////////////
  // Errors //
  ////////////
  error FS_InvalidSplitPercentage();
  error FS_NoBalanceToSplit();

  ////////////
  // Events //
  ////////////
  event SplitPercentSet(uint splitPercent);
  event SubAccountsSet(uint accountA, uint accountB);
  event SubAccountRecovered(uint oldSubAcc, address recipient, uint newSubAcc);
  event BalanceSplit(uint subAcc, uint accountA, uint accountB, int splitAmountA, int splitAmountB);
}
