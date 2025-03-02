// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {PublicLBTSA} from "./PublicLBTSA.sol";
import {LeveragedBasisTSA} from "../../../src/tokenizedSubaccounts/LevBasisTSA.sol";
import "./TSATestUtils.sol";

contract LBTSATestUtils is TSATestUtils {
  using SignedMath for int;

  PublicLBTSA public tsaImplementation;
  PublicLBTSA internal lbtsa;

  LeveragedBasisTSA.LBTSAParams public defaultLBTSAParams = LeveragedBasisTSA.LBTSAParams({
    maxPerpFee: 0.01e18,
    maxBaseLossPerBase: 0.02e18,
    maxBaseLossPerPerp: 0.02e18,
    deltaTarget: 1e18,
    deltaTargetTolerance: 0.5e18,
    leverageFloor: 0.9e18,
    leverageCeil: 3e18,
    emaDecayFactor: 0.0002e18,
    markLossEmaTarget: 0.02e18,
    minSignatureExpiry: 60,
    maxSignatureExpiry: 60 * 60 * 24 * 7
  });

  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
    .CollateralManagementParams({
    feeFactor: 0.01e18,
    spotTransactionLeniency: 1.01e18,
    worstSpotBuyPrice: 1.01e18,
    worstSpotSellPrice: 0.99e18
  });

  function upgradeToLBTSA() internal {
    tsaImplementation = new PublicLBTSA();

    BaseTSA.BaseTSAInitParams memory initParams = BaseTSA.BaseTSAInitParams({
      subAccounts: subAccounts,
      auction: auction,
      cash: cash,
      wrappedDepositAsset: markets["weth"].base,
      manager: srm,
      matching: matching,
      symbol: "LBTSA",
      name: "Leveraged Basis TSA"
    });

    LeveragedBasisTSA.LBTSAInitParams memory lbInitParams = LeveragedBasisTSA.LBTSAInitParams({
      depositModule: depositModule,
      withdrawalModule: withdrawalModule,
      tradeModule: tradeModule,
      baseFeed: markets["weth"].spotFeed,
      perpAsset: markets["weth"].perp
    });

    console.log("address(markets[\"weth\"].perp)", address(markets["weth"].perp));

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(tsaImplementation),
      abi.encodeWithSelector(tsaImplementation.initialize.selector, address(this), initParams, lbInitParams)
    );

    lbtsa = PublicLBTSA(address(proxy));
    tsa = BaseOnChainSigningTSA(address(proxy));
    tsaSubacc = lbtsa.subAccount();
  }

  function setupLBTSA() internal {
    tsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000e18,
        minDepositValue: 1e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );

    LeveragedBasisTSA(address(tsa)).setLBTSAParams(defaultLBTSAParams);
    LeveragedBasisTSA(address(tsa)).setCollateralManagementParams(defaultCollateralManagementParams);

    tsa.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

    tsa.setSigner(signer, true);
  }
}
