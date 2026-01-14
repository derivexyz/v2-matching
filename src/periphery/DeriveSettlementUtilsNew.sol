// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IOptionAsset} from "v2-core/src/interfaces/IOptionAsset.sol";
import {LyraForwardFeed} from "v2-core/src/feeds/LyraForwardFeed.sol";
import {OptionAsset} from "v2-core/src/assets/OptionAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";

import "../interfaces/IMatching.sol";
import {SubAccounts} from "v2-core/src/SubAccounts.sol";

contract DeriveSettlementUtilsNew {
  SubAccounts public subaccounts;

  constructor(SubAccounts _subaccounts) {
    subaccounts = _subaccounts;
  }

  function settleOptionsWithFeedData(
    address manager,
    address option,
    uint[] memory subAccounts,
    bytes[] calldata feedDatas
  ) external {
    for (uint i = 0; i < feedDatas.length; ++i) {
      LyraForwardFeed(address(OptionAsset(option).settlementFeed())).acceptData(feedDatas[i]);
    }

    for (uint i = 0; i < subAccounts.length; ++i) {
      _settleOptions(manager, option, subAccounts[i]);
    }
  }

  function settleOptions(address manager, address option, uint[] memory subAccounts) external {
    for (uint i = 0; i < subAccounts.length; ++i) {
      _settleOptions(manager, option, subAccounts[i]);
    }
  }

  function settleOptionsBySubAccounts(uint[] memory subAccounts) external {
    for (uint i = 0; i < subAccounts.length; ++i) {
      uint subAcc = subAccounts[i];
      address manager = address(subaccounts.manager(subAcc));
      // Capped at 4 options per subaccount... Can repeat if needed
      address[] memory options = new address[](4);

      SubAccounts.AssetBalance[] memory balances = subaccounts.getAccountBalances(subAcc);

      for (uint j = 0; j < balances.length; ++j) {
        // only options use subId for now
        if (balances[j].subId != 0) {
          address asset = address(balances[j].asset);
          for (uint k = 0; k < options.length; ++k) {
            if (options[k] == asset) break;
            if (options[k] == address(0)) {
              options[k] = asset;
              break;
            }
          }
        }
      }

      for (uint j = 0; j < options.length; ++j) {
        if (options[j] == address(0)) break;
        ILiquidatableManager(manager).settleOptions(IOptionAsset(options[j]), uint(subAcc));
      }
    }
  }

  function _settleOptions(address manager, address option, uint subAccounts) internal {
    for (uint i = 0; i < 8; ++i) {
      uint32 account = uint32((subAccounts >> (i * 32)) & 0xFFFFFFFF);
      if (account == 0) break;
      ILiquidatableManager(manager).settleOptions(IOptionAsset(option), uint(account));
    }
  }

  function settlePerps(address manager, uint[] memory subAccounts) external {
    for (uint i = 0; i < subAccounts.length; ++i) {
      _settlePerps(manager, subAccounts[i]);
    }
  }

  function _settlePerps(address manager, uint subAccounts) internal {
    for (uint i = 0; i < 8; ++i) {
      uint32 account = uint32((subAccounts >> (i * 32)) & 0xFFFFFFFF);
      if (account == 0) break;
      ILiquidatableManager(manager).settlePerpsWithIndex(uint(account));
    }
  }
}
