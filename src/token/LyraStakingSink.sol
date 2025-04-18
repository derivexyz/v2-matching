// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";

/// @notice Contract for users to lock up their tokens until owner chooses to free the tokens
contract LyraStakingSink is Ownable {
  IERC20 public token;
  mapping(address => uint) public lockedBalances;
  bool public locked = true;

  /////////////////
  // Constructor //
  /////////////////

  constructor(IERC20 _token) Ownable(msg.sender) {
    token = _token;
  }

  ///////////
  // Admin //
  ///////////

  function recoverERC20(address tokenAddress, uint tokenAmount) external onlyOwner {
    IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
  }

  function setLocked(bool _locked) external onlyOwner {
    locked = _locked;
  }

  ////////////
  // Public //
  ////////////

  function lock(uint amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    lockedBalances[msg.sender] += amount;
    emit Locked(msg.sender, amount);
  }

  function withdraw() external {
    require(!locked, "locked");
    uint amount = lockedBalances[msg.sender];
    lockedBalances[msg.sender] = 0;
    token.transfer(msg.sender, amount);
    emit Withdrawn(msg.sender, amount);
  }

  //////////
  // View //
  //////////

  function getMultipleBalances(address[] memory users) external view returns (uint[] memory) {
    uint[] memory balances = new uint[](users.length);
    for (uint i = 0; i < users.length; ++i) {
      balances[i] = lockedBalances[users[i]];
    }
    return balances;
  }

  ////////////
  // Events //
  ////////////

  event Locked(address indexed user, uint amount);
  event Withdrawn(address indexed user, uint amount);
}
