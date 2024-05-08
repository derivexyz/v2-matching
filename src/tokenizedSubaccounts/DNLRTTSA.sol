// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {StandardManager} from "v2-core/src/risk-managers/StandardManager.sol";
import {PMRM, IPMRM} from "v2-core/src/risk-managers/PMRM.sol";
import {IBaseManager} from "v2-core/src/interfaces/IBaseManager.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseModule} from "../modules/BaseModule.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

import {BaseTSA} from "./BaseTSA.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";

/// @title DNLRTTSA
/// @dev Prices shares in USD, but accepts baseAsset as deposit. Vault intended to try remain delta neutral.
contract DNLRTTSA is BaseTSA {
  ISpotFeed public conversionFeed;

  constructor(BaseTSA.BaseTSAInitParams memory initParams, ISpotFeed _conversionFeed) BaseTSA(initParams) {
    conversionFeed = _conversionFeed;
  }

  ///////////
  // Admin //
  ///////////
  function setConversionFeed(ISpotFeed _conversionFeed) external onlyOwner {
    conversionFeed = _conversionFeed;
  }

  function _getAccountValue() internal view override returns (int) {
    // TODO: must account for lyra system insolvency/withdrawal fee
    (, int mtm) = manager.getMarginAndMarkToMarket(subAccount, true, 0);

    (uint spotPrice,) = conversionFeed.getSpot();
    uint depositAssetBalance = depositAsset.balanceOf(address(this));

    return mtm + int(depositAssetBalance * spotPrice / 1e18);
  }

  // @dev Conversion factor for deposit asset to shares
  function _getDepositWithdrawFactor() internal view override returns (uint) {
    (uint spotPrice,) = conversionFeed.getSpot();
    return spotPrice;
  }
}
