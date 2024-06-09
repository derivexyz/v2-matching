// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "../../../src/tokenizedSubaccounts/CCTSA.sol";

/// @title CCTSAMock
contract CCTSAMock is CoveredCallTSA {
  function _verifyAction(IMatching.Action memory, bytes32) internal virtual override {}
}
