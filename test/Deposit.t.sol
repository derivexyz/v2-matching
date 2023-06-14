// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "./shared/MatchingBase.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract DepositModule is MatchingBase {
  function testSimpleDeposit() public {}
}
