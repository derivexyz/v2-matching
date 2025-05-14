// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "../../../src/tokenizedSubaccounts/shared/BaseOnChainSigningTSA.sol";

/// @title MockTSA
contract MockTSA is BaseOnChainSigningTSA {
  struct MockTSAStorage {
    uint accountValue;
    bool passActions;
  }

  bytes32 private constant MockTSAStorageLocation = 0x1111111111111111111111111111111111111111111111111111111111111111;

  function _getMockTSAStorage() private pure returns (MockTSAStorage storage $) {
    assembly {
      $.slot := MockTSAStorageLocation
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address initialOwner, BaseTSA.BaseTSAInitParams memory initParams) external reinitializer(999) {
    __BaseTSA_init(initialOwner, initParams);

    _getMockTSAStorage().passActions = true;
  }

  ///////////
  // Admin //
  ///////////
  function setPassActions(bool _passActions) external onlyOwner {
    _getMockTSAStorage().passActions = _passActions;
  }

  function setAccountValue(uint _accountValue) external onlyOwner {
    _getMockTSAStorage().accountValue = _accountValue;
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory, bytes32, bytes memory) internal virtual override {
    require(_getMockTSAStorage().passActions, "MockTSA: actions are disabled");
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getAccountValue(bool) internal view override returns (uint) {
    return _getMockTSAStorage().accountValue;
  }
}
