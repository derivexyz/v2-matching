// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {MatchingBase} from "./shared/MatchingBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";
import {TransferModule} from "src/modules/TransferModule.sol";

/**
 * @notice basic test for matching core contract
 */
contract MatchingBasicTest is MatchingBase {
  uint public newKey = 909886112;
  address public newSigner = vm.addr(newKey);

  function testGetDomainSeparator() public {
    matching.domainSeparator();
  }

  function testSetExecutor() public {
    address newExecutor = address(0xaaaa);
    matching.setTradeExecutor(newExecutor, true);
    assertEq(matching.tradeExecutors(newExecutor), true);

    matching.setTradeExecutor(newExecutor, false);
    assertEq(matching.tradeExecutors(newExecutor), false);
  }
}
