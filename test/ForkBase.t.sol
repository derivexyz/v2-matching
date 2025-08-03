// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {UtilBase} from "../scripts/shared/Utils.sol";

contract ForkBase is UtilBase, Test {
  modifier checkFork() {
    if (block.chainid == 31337) {
      vm.skip(true);
    }
    _;
  }

  function _call(address target, bytes memory data) internal returns (bytes memory) {
//    console.log(target);
//    console.log(",0,");
//    console.logBytes(data);
    (bool success, bytes memory result) = target.call(data);
    require(success, "call failed");
    return result;
  }
}
