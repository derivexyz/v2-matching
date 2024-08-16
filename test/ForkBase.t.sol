// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract ForkBase is Test {
  constructor() {}

  modifier skipped() {
    vm.skip(true);
    _;
  }
}
