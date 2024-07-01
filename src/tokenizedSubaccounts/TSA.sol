// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "openzeppelin-upgradeable/token/ERC20/extensions/ERC20WrapperUpgradeable.sol";

contract TokenizedSubAccount is ERC20WrapperUpgradeable {
  constructor() {
    _disableInitializers();
  }

  function initialize(string memory name, string memory symbol, IERC20 underlyingToken) external initializer {
    __ERC20_init(name, symbol);
    __ERC20Wrapper_init(underlyingToken);
  }
}
