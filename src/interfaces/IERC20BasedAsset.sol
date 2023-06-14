// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

// TODO: remove and replace with v2-core version later
interface IERC20BasedAsset {
  function wrappedAsset() external view returns (IERC20Metadata);
  function deposit(uint recipientAccount, uint assetAmount) external;
  function withdraw(uint accountId, uint assetAmount, address recipient) external;

  event Deposit(uint indexed accountId, address indexed depositor, uint amountAsset);
  event Withdraw(uint indexed accountId, address indexed recipient, uint amountAsset);
}
