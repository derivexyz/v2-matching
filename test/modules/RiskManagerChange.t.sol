// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {RiskManagerChangeModule, IRiskManagerChangeModule} from "src/modules/RiskManagerChangeModule.sol";
import {MockManager} from "v2-core/test/shared/mocks/MockManager.sol";

contract RiskManagerChangeModuleTest is MatchingBase {
  function testCanChangeManager() public {
    MockManager manager = new MockManager(address(subAccounts));

    bytes memory newManagerData = abi.encode(manager);
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, cam, cam, camPk
    );

    _verifyAndMatch(actions, "");

    assertEq(address(subAccounts.manager(camAcc)), address(manager));
  }

  function testCannotPassInInvalidActionLength() public {
    bytes memory newManagerData = abi.encode(address(0xbb));
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    actions[0] = _createFullSignedAction(
      camAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, cam, cam, camPk
    );
    actions[1] = _createFullSignedAction(
      dougAcc, 0, address(changeModule), newManagerData, block.timestamp + 1 days, doug, doug, dougPk
    );

    vm.expectRevert(IRiskManagerChangeModule.RMCM_InvalidActionLength.selector);
    _verifyAndMatch(actions, "");
  }
}
