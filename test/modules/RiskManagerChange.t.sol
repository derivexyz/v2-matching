// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";
import {RiskManagerChangeModule, IRiskManagerChangeModule} from "src/modules/RiskManagerChangeModule.sol";
import {MockManager} from "v2-core/test/shared/mocks/MockManager.sol";

contract RiskManagerChangeModuleTest is MatchingBase {
  function testCanChangeManager() public {
    MockManager manager = new MockManager(address(subAccounts));

    bytes memory newManagerData = abi.encode(manager);
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(orders, "");

    assertEq(address(subAccounts.manager(camAcc)), address(manager));
  }

  function testCannotPassInInvalidOrderLength() public {
    bytes memory newManagerData = abi.encode(address(0xbb));
    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](2);
    orders[0] = _createFullSignedOrder(
      camAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, cam, cam, camPk
    );
    orders[1] = _createFullSignedOrder(
      dougAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(IRiskManagerChangeModule.RMCM_InvalidOrderLength.selector);
    _verifyAndMatch(orders, "");
  }
}
