// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBaseModule} from "./IBaseModule.sol";

interface ITransferModule is IBaseModule {
  struct TransferData {
    uint toAccountId;
    address managerForNewAccount;
    Transfers[] transfers;
  }

  struct Transfers {
    address asset;
    uint subId;
    int amount;
  }

  error TFM_InvalidFromAccount();
  error TFM_InvalidTransferActionLength();
  error TFM_InvalidRecipientOwner();
  error TFM_ToAccountMismatch();
}
