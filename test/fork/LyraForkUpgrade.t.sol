pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../src/periphery/LyraSettlementUtils.sol";
import {BaseTSA} from "../../src/tokenizedSubaccounts/BaseTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IMatching} from "../../src/interfaces/IMatching.sol";
import {IDepositModule} from "../../src/interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../../src/interfaces/IWithdrawalModule.sol";
import {ITradeModule} from "../../src/interfaces/ITradeModule.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import "../../src/tokenizedSubaccounts/CCTSA.sol";
import "../../src/tokenizedSubaccounts/PPTSA.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenizedSubAccount} from "../../src/tokenizedSubaccounts/TSA.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TSAShareHandler} from "../../src/tokenizedSubaccounts/TSAShareHandler.sol";
import "v2-core/src/l2/LyraERC20.sol";
import "../../src/Matching.sol";
import "v2-core/src/assets/WLWrappedERC20Asset.sol";
import "../../src/modules/RfqModule.sol";
import "v2-core/src/SubAccounts.sol";
import {ForkBase} from "./ForkBase.t.sol";

contract LyraForkUpgradeTest is ForkBase {
  CollateralManagementTSA.CollateralManagementParams public defaultCollateralManagementParams = CollateralManagementTSA
    .CollateralManagementParams({
    feeFactor: 10000000000000000,
    spotTransactionLeniency: 1050000000000000000,
    worstSpotSellPrice: 985000000000000000,
    worstSpotBuyPrice: 1015000000000000000
  });

  PrincipalProtectedTSA.PPTSAParams public defaultLrtppTSAParams = PrincipalProtectedTSA.PPTSAParams({
    maxMarkValueToStrikeDiffRatio: 700000000000000000,
    minMarkValueToStrikeDiffRatio: 100000000000000000,
    strikeDiff: 200000000000000000000,
    maxTotalCostTolerance: 2000000000000000000,
    maxLossOrGainPercentOfTVL: 20000000000000000,
    negMaxCashTolerance: 20000000000000000,
    minSignatureExpiry: 300,
    maxSignatureExpiry: 1800,
    optionMinTimeToExpiry: 21000,
    optionMaxTimeToExpiry: 691200,
    maxNegCash: -100000000000000000000000,
    rfqFeeFactor: 1000000000000000000
  });

  function setUp() external {}

  function testForkUpgrade() external skipped {
    address deployer = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;

    vm.deal(deployer, 1 ether);
    vm.startPrank(deployer);
    string memory tsaName = "sUSDeBULL";

    ProxyAdmin proxyAdmin = ProxyAdmin(_getContract(tsaName, "proxyAdmin"));

    PrincipalProtectedTSA implementation = PrincipalProtectedTSA(_getContract(tsaName, "implementation"));

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(_getContract(tsaName, "proxy")),
      address(0xa2F1C5b4d8e0b3835025a9E5D45cFF6226261f58),
      abi.encodeWithSelector(
        implementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getContract("core", "subAccounts")),
          auction: DutchAuction(_getContract("core", "auction")),
          cash: CashAsset(_getContract("core", "cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getContract("sUSDe", "base")),
          manager: ILiquidatableManager(_getContract("core", "srm")),
          matching: IMatching(_getContract("matching", "matching")),
          symbol: tsaName,
          name: string.concat("sUSDe ", "Principal Protected Bull Call Spread")
        }),
        PrincipalProtectedTSA.PPTSAInitParams({
          baseFeed: ISpotFeed(_getContract("sUSDe", "spotFeed")),
          depositModule: IDepositModule(_getContract("matching", "deposit")),
          withdrawalModule: IWithdrawalModule(_getContract("matching", "withdrawal")),
          tradeModule: ITradeModule(_getContract("matching", "trade")),
          optionAsset: IOptionAsset(_getContract("ETH", "option")),
          rfqModule: IRfqModule(_getContract("matching", "rfq")),
          isCallSpread: true,
          isLongSpread: true
        })
      )
    );

    PrincipalProtectedTSA pptsa = PrincipalProtectedTSA(address(_getContract(tsaName, "proxy")));

    pptsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 100000000e18,
        minDepositValue: 0.01e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );
    pptsa.setPPTSAParams(defaultLrtppTSAParams);
    pptsa.setCollateralManagementParams(defaultCollateralManagementParams);
    pptsa.setShareKeeper(deployer, true);
    pptsa.setSigner(deployer, true);
    vm.stopPrank();
    _verifyAndMatchDeposit(pptsa);
    _verifyTakerTrade(pptsa);
    _verifyMakerTrade(pptsa);
    _verifyWithdraw(pptsa);
  }

  function _verifyAndMatchDeposit(PrincipalProtectedTSA pptsa) internal {
    address susde = _getContract("shared", "susde");
    address deployer = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;
    Matching matching = Matching(_getContract("matching", "matching"));
    LyraERC20 susdeCoin = LyraERC20(susde);
    address proxyAddress = _getContract("sUSDeBULL", "proxy");

    vm.prank(proxyAddress);
    susdeCoin.approve(deployer, 11e18);
    vm.startPrank(deployer);
    susdeCoin.transferFrom(proxyAddress, deployer, 10e18);

    WLWrappedERC20Asset wrappedDepositAsset = WLWrappedERC20Asset(_getContract("sUSDe", "base"));
    wrappedDepositAsset.wrappedAsset().approve(address(pptsa), 11e18);
    wrappedDepositAsset.setWhitelistEnabled(false);
    uint depositId = pptsa.initiateDeposit(1e18, deployer);
    pptsa.processDeposit(depositId);

    bytes memory depositData = abi.encode(
      IDepositModule.DepositData({amount: 10e18, asset: _getContract("sUSDe", "base"), managerForNewAccount: address(0)})
    );

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: pptsa.subAccount(),
      nonce: 1,
      module: IDepositModule(_getContract("matching", "deposit")),
      data: depositData,
      expiry: block.timestamp + 8 minutes,
      owner: address(pptsa),
      signer: address(pptsa)
    });

    pptsa.signActionData(action, "");
    bytes memory encodedAction = abi.encode(action);
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](1);
    bytes[] memory signatures = new bytes[](1);
    actions[0] = action;

    matching.setTradeExecutor(deployer, true);
    vm.stopPrank();
    vm.prank(deployer);
    matching.verifyAndMatch(actions, signatures, encodedAction);
  }

  function _verifyTakerTrade(PrincipalProtectedTSA pptsa) internal {
    address deployer = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;
    OptionAsset optionAsset = OptionAsset(_getContract("ETH", "option"));
    RfqModule rfqModule = RfqModule(_getContract("matching", "rfq"));

    uint higherPrice = 3.6e18;
    uint highStrike = 2900e18;
    uint lowerPrice = 30e18;
    uint lowStrike = 2700e18;

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](2);
    trades[0] = IRfqModule.TradeData({
      asset: address(optionAsset),
      subId: OptionEncoding.toSubId(uint64(1723708800), highStrike, true), // TODO: Fix to next friday 8 AM UTC
      price: higherPrice,
      amount: 0.0001e18
    });

    trades[1] = IRfqModule.TradeData({
      asset: address(optionAsset),
      subId: OptionEncoding.toSubId(uint64(1723708800), lowStrike, true),
      price: lowerPrice,
      amount: -0.0001e18
    });

    IRfqModule.TakerOrder memory takerOrder =
      IRfqModule.TakerOrder({orderHash: keccak256(abi.encode(trades)), maxFee: 0});

    // taker order
    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: pptsa.subAccount(),
      nonce: 2,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(pptsa),
      signer: address(pptsa)
    });
    vm.prank(deployer);
    pptsa.signActionData(action, abi.encode(trades));
  }

  function _verifyMakerTrade(PrincipalProtectedTSA pptsa) internal {
    address deployer = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;
    OptionAsset optionAsset = OptionAsset(_getContract(_readV2CoreDeploymentFile("ETH"), "option"));
    RfqModule rfqModule = RfqModule(_getContract(_readMatchingDeploymentFile("matching"), "rfq"));

    uint higherPrice = 3.6e18;
    uint highStrike = 2900e18;
    uint lowerPrice = 30e18;
    uint lowStrike = 2700e18;

    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](2);
    trades[0] = IRfqModule.TradeData({
      asset: address(optionAsset),
      subId: OptionEncoding.toSubId(uint64(1723708800), highStrike, true), // TODO: Fix to next friday 8 AM UTC
      price: higherPrice,
      amount: -0.0001e18
    });

    trades[1] = IRfqModule.TradeData({
      asset: address(optionAsset),
      subId: OptionEncoding.toSubId(uint64(1723708800), lowStrike, true),
      price: lowerPrice,
      amount: 0.0001e18
    });

    IRfqModule.RfqOrder memory makerOrder = IRfqModule.RfqOrder({maxFee: 0, trades: trades});

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: pptsa.subAccount(),
      nonce: 3,
      module: IMatchingModule(address(rfqModule)),
      data: abi.encode(makerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(pptsa),
      signer: address(pptsa)
    });
    vm.prank(deployer);
    pptsa.signActionData(action, "");
  }

  function _verifyWithdraw(PrincipalProtectedTSA pptsa) internal {
    address deployer = 0xB176A44D819372A38cee878fB0603AEd4d26C5a5;
    IWithdrawalModule.WithdrawalData memory data = IWithdrawalModule.WithdrawalData({
      asset: _getContract(_readV2CoreDeploymentFile("sUSDe"), "base"),
      assetAmount: 10e18
    });

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: pptsa.subAccount(),
      nonce: 5,
      module: IWithdrawalModule(_getContract(_readMatchingDeploymentFile("matching"), "withdrawal")),
      data: abi.encode(data),
      expiry: block.timestamp + 8 minutes,
      owner: address(pptsa),
      signer: address(pptsa)
    });
    vm.prank(deployer);
    pptsa.signActionData(action, "");
  }
}
