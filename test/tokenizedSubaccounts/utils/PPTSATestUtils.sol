// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {PrincipalProtectedTSA} from "../../../src/tokenizedSubaccounts/PPTSA.sol";
import "./TSATestUtils.sol";

contract PPTSATestUtils is TSATestUtils {
  using SignedMath for int;

  PrincipalProtectedTSA public tsaImplementation;
  PrincipalProtectedTSA internal pptsa;

  PrincipalProtectedTSA.PPTSAParams public defaultPPTSAParams = PrincipalProtectedTSA.PPTSAParams({
    maxMarkValueToStrikeDiffRatio: 1e18,
    minMarkValueToStrikeDiffRatio: 1,
    strikeDiff: 400e18,
    maxTotalCostTolerance: 1e18,
    maxLossOrGainPercentOfTVL: 2e17,
    negMaxCashTolerance: 0.1e18,
    minSignatureExpiry: 5 minutes,
    maxSignatureExpiry: 30 minutes,
    optionMinTimeToExpiry: 1 days,
    optionMaxTimeToExpiry: 30 days,
    maxNegCash: -100e18,
    rfqFeeFactor: 0.02e18
  });

  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
    .CollateralManagementParams({
    feeFactor: 0.01e18,
    spotTransactionLeniency: 1.01e18,
    worstSpotBuyPrice: 1.01e18,
    worstSpotSellPrice: 0.99e18
  });

  function upgradeToPPTSA(string memory market, bool doesCallSpreads, bool isLong) internal {
    IWrappedERC20Asset wrappedDepositAsset;
    ISpotFeed baseFeed;
    IOptionAsset optionAsset;

    // if market is USDC collateral (for decimal tests)
    if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("usdc"))) {
      wrappedDepositAsset = IWrappedERC20Asset(address(cash));
      baseFeed = stableFeed;
      optionAsset = IOptionAsset(address(0));
    } else {
      wrappedDepositAsset = markets[market].base;
      baseFeed = markets[market].spotFeed;
      optionAsset = markets[market].option;
    }

    tsaImplementation = new PrincipalProtectedTSA();

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(tsaImplementation),
      abi.encodeWithSelector(
        tsaImplementation.initialize.selector,
        address(this),
        BaseTSA.BaseTSAInitParams({
          subAccounts: subAccounts,
          auction: auction,
          cash: cash,
          wrappedDepositAsset: wrappedDepositAsset,
          manager: srm,
          matching: matching,
          symbol: "Tokenised SubAccount",
          name: "TSA",
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
        }),
        PrincipalProtectedTSA.PPTSAInitParams({
          baseFeed: baseFeed,
          depositModule: depositModule,
          withdrawalModule: withdrawalModule,
          tradeModule: tradeModule,
          optionAsset: optionAsset,
          rfqModule: rfqModule,
          isCallSpread: doesCallSpreads,
          isLongSpread: isLong
        })
      )
    );
    tsa = BaseOnChainSigningTSA(address(proxy));
    pptsa = PrincipalProtectedTSA(address(tsa));
    pptsa.setPPTSAParams(defaultPPTSAParams);
    tsaSubacc = pptsa.subAccount();
  }

  function setupPPTSA() internal {
    PrincipalProtectedTSA(address(tsa)).setCollateralManagementParams(defaultCollateralManagementParams);

    tsa.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

    tsa.setSigner(signer, true);
  }

  function _setupPPTSAWithDeposit(bool isCallSpread, bool isLongSpread) internal {
    deployPredeposit(address(markets[MARKET].erc20));
    upgradeToPPTSA(MARKET, isCallSpread, isLongSpread);
    setupPPTSA();
    _depositToTSA(100e18);
    _executeDeposit(100e18);
  }
}
