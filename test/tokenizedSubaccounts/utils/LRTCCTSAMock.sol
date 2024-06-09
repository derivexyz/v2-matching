// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "../../../src/tokenizedSubaccounts/LRTCCTSA.sol";

/// @title LRTCCTSAMock
contract LRTCCTSAMock is LRTCCTSA {
  function _verifyAction(IMatching.Action memory, bytes32) internal virtual override {}
}
