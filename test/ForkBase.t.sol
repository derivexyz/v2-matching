// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UtilBase} from "../scripts/shared/Utils.sol";

contract ForkBase is UtilBase, Test {
  modifier checkFork() {
    if (block.chainid == 31337) {
      vm.skip(true);
    }
    _;
  }

}