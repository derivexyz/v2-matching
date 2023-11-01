// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Matching} from "../src/Matching.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";
import {SubAccountCreator} from "../src/periphery/SubAccountCreator.sol";


struct NetworkConfig {
  address subAccounts;
  address cash;
}

struct Deployment {
  // matching contract
  Matching matching;
  // modules
  DepositModule deposit;
  TradeModule trade;
  TransferModule transfer;
  WithdrawalModule withdrawal;
  // helper
  SubAccountCreator subAccountCreator;
}