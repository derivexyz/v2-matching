// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {RiskManagerChangeModule} from "src/modules/RiskManagerChangeModule.sol";
import {MockManager} from "v2-core/test/shared/mocks/MockManager.sol";

contract ChangeManagerModuleTest is MatchingBase {
  function testCanChangeManager() public {
    MockManager manager = new MockManager(address(subAccounts));

    bytes memory newManagerData = abi.encode(manager);
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, "");

    assertEq(address(subAccounts.manager(camAcc)), address(manager));
  }

  function testCannotPassInInvalidOrderLength() public {
    bytes memory newManagerData = abi.encode(address(0xbb));
    OrderVerifier.SignedOrder[] memory orders = new OrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(RiskManagerChangeModule.RMCM_InvalidOrderLength.selector);
    _verifyAndMatch(orders, "");
  }
}
