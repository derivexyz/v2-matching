// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {PublicLBTSA} from "./PublicLBTSA.sol";
import "./TSATestUtils.sol";
import {EMAGeneralisedTSA} from "../../../src/tokenizedSubaccounts/EMAGeneralisedTSA.sol";

contract EGTSATestUtils is TSATestUtils {
  using SignedMath for int;

  EMAGeneralisedTSA public tsaImplementation;

  EMAGeneralisedTSA internal gtsa;

  function upgradeToGTSA() internal {
    tsaImplementation = new EMAGeneralisedTSA();

    BaseTSA.BaseTSAInitParams memory initParams = BaseTSA.BaseTSAInitParams({
      subAccounts: subAccounts,
      auction: auction,
      cash: cash,
      wrappedDepositAsset: markets[MARKET].base,
      manager: srm,
      matching: matching,
      symbol: "GTSA",
      name: "GTSA",
      initialParams: BaseTSA.TSAParams({
        depositCap: 10000e18,
        minDepositValue: 1e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0),
        performanceFeeWindow: 1 weeks,
        performanceFee: 0
      })
    });

    EMAGeneralisedTSA.GTSAInitParams memory gInitParams = EMAGeneralisedTSA.GTSAInitParams({
      baseFeed: markets[MARKET].spotFeed,
      depositModule: depositModule,
      withdrawalModule: withdrawalModule,
      tradeModule: tradeModule,
      rfqModule: rfqModule
    });

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(tsaImplementation),
      abi.encodeWithSelector(tsaImplementation.initialize.selector, address(this), initParams, gInitParams)
    );

    gtsa = EMAGeneralisedTSA(address(proxy));
    tsa = BaseOnChainSigningTSA(address(proxy));
    tsaSubacc = gtsa.subAccount();
  }

  function setupGTSA() internal {
    EMAGeneralisedTSA(address(tsa)).setGTSAParams(0.0002e18, 0.02e18);

    tsa.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

    tsa.setSigner(signer, true);
  }
}
