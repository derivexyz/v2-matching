// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "./shared/MatchingBase.t.sol";
import {OrderVerifier} from "../src/OrderVerifier.sol";
import {Matching, IMatching} from "../src/Matching.sol";
import {BadModule} from "./mock/BadModule.sol";
import {IOrderVerifier} from "src/interfaces/IOrderVerifier.sol";

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

    IOrderVerifier.SignedOrder[] memory orders = new IOrderVerifier.SignedOrder[](1);
    orders[0] = _createFullSignedOrder(camAcc, 0, address(badModule), "", block.timestamp + 1 days, cam, cam, camPk);

    vm.expectRevert(IMatching.M_OnlyAllowedModule.selector);
    _verifyAndMatch(orders, "");

    matching.setAllowedModule(address(badModule), true);
    vm.expectRevert(IMatching.M_AccountNotReturned.selector);
    _verifyAndMatch(orders, "");
  }
}
