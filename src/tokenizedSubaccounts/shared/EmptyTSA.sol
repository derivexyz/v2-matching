// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "lyra-utils/decimals/SignedDecimalMath.sol";

import {BaseOnChainSigningTSA} from "./BaseOnChainSigningTSA.sol";
import {ITradeModule} from "../../interfaces/ITradeModule.sol";
import {IMatching} from "../../interfaces/IMatching.sol";
import {IDepositModule} from "../../interfaces/IDepositModule.sol";

abstract contract EmptyTSA is BaseOnChainSigningTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  //////////////
  // Deposits //
  //////////////
  function _verifyDepositAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    IDepositModule.DepositData memory depositData = abi.decode(action.data, (IDepositModule.DepositData));

    if (depositData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert ETSA_InvalidAsset();
    }

    if (depositData.amount > tsaAddresses.depositAsset.balanceOf(address(this)) - totalPendingDeposits()) {
      revert ETSA_DepositingTooMuch();
    }
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getAccountValue(bool includePending) internal view override returns (uint) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    uint depositAssetBalance = tsaAddresses.depositAsset.balanceOf(address(this));
    if (!includePending) {
      depositAssetBalance -= totalPendingDeposits();
    }

    return _getConvertedMtM(true) + depositAssetBalance;
  }

  function _getConvertedMtM(bool nativeDecimals) internal view returns (uint) {
    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    // Note: scenario 0 wont calculate full margin for PMRM subaccounts
    (, int mtm) = tsaAddresses.manager.getMarginAndMarkToMarket(subAccount(), false, 0);
    uint spotPrice = _getBasePrice();

    // convert to depositAsset value but in 18dp
    int convertedMtM = mtm.divideDecimal(spotPrice.toInt256());

    if (nativeDecimals) {
      // Now convert to appropriate decimals
      uint8 decimals = tsaAddresses.depositAsset.decimals();
      if (decimals > 18) {
        convertedMtM = convertedMtM * int(10 ** (decimals - 18));
      } else if (decimals < 18) {
        convertedMtM = convertedMtM / int(10 ** (18 - decimals));
      }
    }

    // Might not be technically insolvent (could have enough depositAsset to cover the deficit), but we block deposits
    if (convertedMtM < 0) {
      revert ETSA_PositionInsolvent();
    }

    return uint(convertedMtM);
  }

  function _getBasePrice() internal view virtual returns (uint spotPrice);

  error ETSA_InvalidAsset();
  error ETSA_DepositingTooMuch();
  error ETSA_PositionInsolvent();
}
