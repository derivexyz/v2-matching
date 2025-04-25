// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "./TSATestUtils.sol";
import {CoveredCallTSA} from "../../../src/tokenizedSubaccounts/CCTSA.sol";

contract CCTSATestUtils is TSATestUtils {
  using SignedMath for int;

  CoveredCallTSA public tsaImplementation;
  CoveredCallTSA internal cctsa;

  CoveredCallTSA.CCTSAParams public defaultCCTSAParams = CoveredCallTSA.CCTSAParams({
    minSignatureExpiry: 5 minutes,
    maxSignatureExpiry: 30 minutes,
    optionVolSlippageFactor: 0.5e18,
    optionMaxDelta: 0.4e18,
    optionMaxNegCash: -100e18,
    optionMinTimeToExpiry: 1 days,
    optionMaxTimeToExpiry: 30 days
  });

  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
    .CollateralManagementParams({
    feeFactor: 0.01e18,
    spotTransactionLeniency: 1.01e18,
    worstSpotBuyPrice: 1.01e18,
    worstSpotSellPrice: 0.99e18
  });

  function upgradeToCCTSA(string memory market) internal {
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

    tsaImplementation = new CoveredCallTSA();

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
        CoveredCallTSA.CCTSAInitParams({
          baseFeed: baseFeed,
          depositModule: depositModule,
          withdrawalModule: withdrawalModule,
          tradeModule: tradeModule,
          optionAsset: optionAsset
        })
      )
    );

    tsa = BaseOnChainSigningTSA(address(proxy));
    tsaSubacc = tsa.subAccount();
    cctsa = CoveredCallTSA(address(proxy));
  }

  function setupCCTSA() internal {
    CoveredCallTSA(address(tsa)).setCCTSAParams(defaultCCTSAParams);
    CoveredCallTSA(address(tsa)).setCollateralManagementParams(defaultCollateralManagementParams);

    tsa.setShareKeeper(address(this), true);

    signerPk = 0xBEEF;
    signer = vm.addr(signerPk);

    tsa.setSigner(signer, true);
  }
}
