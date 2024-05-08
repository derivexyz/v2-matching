// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract TSAPreDeposit is Ownable2Step {
  IERC20Metadata public depositAsset;
  mapping(address => uint) public deposits;
  uint public depositCap;

  constructor(IERC20Metadata _depositAsset) Ownable2Step() {
    depositAsset = _depositAsset;
  }

  ///////////
  // Admin //
  ///////////

  function migrate() external onlyOwner {
    depositAsset.transfer(owner(), depositAsset.balanceOf(address(this)));
  }

  function setDepositCap(uint _depositCap) external onlyOwner {
    depositCap = _depositCap;
  }

  //////////////////
  // User Actions //
  //////////////////

  function deposit(uint amount) external {
    depositAsset.transferFrom(msg.sender, address(this), amount);
    deposits[msg.sender] += amount;

    require(depositAsset.balanceOf(address(this)) <= depositCap, "Deposit exceeds cap");

    emit Deposit(msg.sender, amount);
  }

  function withdraw(uint amount) external {
    require(deposits[msg.sender] >= amount, "Insufficient balance");
    deposits[msg.sender] -= amount;
    depositAsset.transfer(msg.sender, amount);

    emit Withdrawal(msg.sender, amount);
  }

  ////////////
  // Events //
  ////////////

  event Deposit(address indexed account, uint amount);
  event Withdrawal(address indexed account, uint amount);
}
