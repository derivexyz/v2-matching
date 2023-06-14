// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "./shared/MatchingBase.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract DepositModule is MatchingBase {
  function testSimpleDeposit() public {
    bytes depositData = _encodeDepositData(1e18, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order =
      _createUnsignedOrder(aliceAcc, 0, depositModule, depositData, block.timestamp + 1 days, alice);

    int aliceBalBefore = subAccounts.getBalance(aliceAcc, cash, 0);
    console2.log("Before:", aliceBalBefore);

    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    matching.verifyAndMatch(orders, 0);
    
    int aliceBalAfter = subAccounts.getBalance(aliceAcc, cash, 0);
    console2.log("After:", aliceBalAfter);
  }
  
  function testDepositToNewAccount() public {
    bytes depositData = _encodeDepositData(1e18, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order =
      _createUnsignedOrder(0, 0, depositModule, depositData, block.timestamp + 1 days, alice);

    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    matching.verifyAndMatch(orders, 0);

  }


}
