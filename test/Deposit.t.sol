// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract DepositModuleTest is MatchingBase {
  function testSimpleDeposit() public {
     usdc.mint(alice, 1e18);

    bytes memory depositData = _encodeDepositData(1e18, address(cash), address(pmrm));
    OrderVerifier.SignedOrder memory order =
      _createUnsignedOrder(aliceAcc, 0, address(depositModule), depositData, block.timestamp + 1 days, alice);

    int aliceBalBefore = subAccounts.getBalance(aliceAcc, cash, 0);
    console2.log("Before:", aliceBalBefore);

    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = order;
    
    IERC20Metadata cashToken = IERC20BasedAsset(address(cash)).wrappedAsset();

    vm.startPrank(alice);
    console2.log("Cashe address", address(cashToken));
    cashToken.approve(address(depositModule), 1e18);
     console2.log("allowance", cashToken.allowance(alice, address(depositModule)));
     console2.log("owner", alice);
     console2.log("depos", address(depositModule));
    console2.log("balance", cashToken.balanceOf(alice));
    vm.stopPrank();

    address aliceOwner = subAccounts.ownerOf(aliceAcc);
    console2.log("aliceOwner", aliceOwner);
    _verifyAndMatch(orders, bytes(""));
    
    int aliceBalAfter = subAccounts.getBalance(aliceAcc, cash, 0);
    console2.log("After:", aliceBalAfter);
  }

  // function testDepositToNewAccount() public {
  //   bytes memory depositData = _encodeDepositData(1e18, address(cash), address(pmrm));
  //   OrderVerifier.SignedOrder memory order =
  //     _createUnsignedOrder(0, 0, depositModule, depositData, block.timestamp + 1 days, alice);

  //   OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
  //   orders[0] = order;

  //   _verifyAndMatch(orders, bytes(""));

  // }
}
