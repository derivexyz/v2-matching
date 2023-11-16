// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";

interface IDepositModule is IBaseModule {
  struct DepositData {
    uint amount;
    address asset;
    address managerForNewAccount;
  }

  error DM_InvalidDepositActionLength();
}
