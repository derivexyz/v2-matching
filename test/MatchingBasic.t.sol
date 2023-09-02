// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "./shared/MatchingBase.t.sol";
import {ActionVerifier} from "../src/ActionVerifier.sol";
import {Matching, IMatching} from "../src/Matching.sol";
import {BadModule} from "./mock/BadModule.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";

/**
 * @notice basic test for matching core contract
 */
contract MatchingBasicTest is MatchingBase {
  uint public newKey = 909886112;
  address public newSigner = vm.addr(newKey);

  function testGetDomainSeparator() public view {
    matching.domainSeparator();
  }

  function testSetExecutor() public {
    address newExecutor = address(0xaaaa);
    matching.setTradeExecutor(newExecutor, true);
    assertEq(matching.tradeExecutors(newExecutor), true);

    matching.setTradeExecutor(newExecutor, false);
    assertEq(matching.tradeExecutors(newExecutor), false);
  }

  function testCannotUseModuleThatDoesNotReturnAccounts() public {
    BadModule badModule = new BadModule();

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);
    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(badModule), "", block.timestamp + 1 days, cam, cam, camPk);

    vm.expectRevert(IMatching.M_OnlyAllowedModule.selector);
    _verifyAndMatch(actions, signatures, "");

    matching.setAllowedModule(address(badModule), true);
    vm.expectRevert(IMatching.M_AccountNotReturned.selector);
    _verifyAndMatch(actions, signatures, "");
  }

  function testCannotExecuteActionsForDifferentModules() public {
    BadModule badModule = new BadModule();

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);
    (actions[0], signatures[0]) =
      _createActionAndSign(camAcc, 0, address(depositModule), "", block.timestamp + 1 days, cam, cam, camPk);
    (actions[1], signatures[1]) =
      _createActionAndSign(camAcc, 0, address(badModule), "", block.timestamp + 1 days, cam, cam, camPk);

    vm.expectRevert(IMatching.M_MismatchedModule.selector);
    _verifyAndMatch(actions, signatures, "");
  }

  function testCanSendERC20Out() public {
    uint stuckAmount = 1000e6;
    uint usdcBefore = usdc.balanceOf(address(this));
    usdc.mint(address(matching), stuckAmount);

    matching.withdrawERC20(address(usdc), address(this), stuckAmount);

    assertEq(usdc.balanceOf(address(this)), usdcBefore + stuckAmount);
    assertEq(usdc.balanceOf(address(matching)), 0);
  }
}
