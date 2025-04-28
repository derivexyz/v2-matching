import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "../utils/GTSATestUtils.sol";

//# Test Cases for GeneralisedTSA

contract GeneralisedTSA_Tests is GTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToGTSA();
    setupGTSA();
  }

  function test_init() external {
    //## Initialization Tests
    //- Initialize with valid parameters and verify all modules are set correctly
    //- Attempt re-initialization (should fail with reinitializer modifier)
    //- Verify deposit asset approval to deposit module after initialization

    (ISpotFeed sf, IDepositModule dm, IWithdrawalModule wm, ITradeModule tm, IRfqModule rm) = gtsa.getGTSAAddresses();

    vm.assertEq(address(sf), address(markets[MARKET].spotFeed));
    vm.assertEq(address(dm), address(depositModule));
    vm.assertEq(address(wm), address(withdrawalModule));
    vm.assertEq(address(tm), address(tradeModule));
    vm.assertEq(address(rm), address(rfqModule));

    vm.assertEq(gtsa.getBasePrice(), MARKET_REF_SPOT);

    (int markLossEma, uint markLossLastTs) = gtsa.getEmaValues();

    vm.assertEq(markLossEma, 0);
    vm.assertEq(markLossLastTs, 0);

    vm.expectRevert(Initializable.InvalidInitialization.selector);
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
        }),
        GeneralisedTSA.GTSAInitParams({
          baseFeed: markets[MARKET].spotFeed,
          depositModule: depositModule,
          withdrawalModule: withdrawalModule,
          tradeModule: tradeModule,
          rfqModule: rfqModule
        })
      )
    );

    // Check deposit asset approval to the deposit module
    vm.assertEq(markets[MARKET].erc20.allowance(address(gtsa), address(depositModule)), type(uint).max);
  }

  //## Admin Function Tests
  //- Set valid EMA parameters (emaDecayFactor > 0, markLossEmaTarget < 0.5e18)
  //- Set invalid EMA parameters and verify revert (emaDecayFactor = 0)
  //- Set invalid EMA parameters and verify revert (markLossEmaTarget >= 0.5e18)
  //- Reset decay parameters and verify markLossLastTs updated to current timestamp
  //- Enable various assets and verify they're properly recorded
  //- Verify only owner can call admin functions
  function test_adminFunctions() external {
    // Set valid EMA parameters
    gtsa.setGTSAParams(0.001e18, 0.05e18);
    (int markLossEma, uint markLossLastTs) = gtsa.getEmaValues();
    vm.assertEq(markLossEma, 0);
    vm.assertEq(markLossLastTs, 0);

    // Set invalid EMA parameters and verify revert
    vm.expectRevert(GeneralisedTSA.GT_InvalidParams.selector);
    gtsa.setGTSAParams(0, 0.02e18);

    vm.expectRevert(GeneralisedTSA.GT_InvalidParams.selector);
    gtsa.setGTSAParams(0.0002e18, 0.6e18);

    // Reset decay parameters
    gtsa.resetDecay();
    (markLossEma, markLossLastTs) = gtsa.getEmaValues();
    vm.assertEq(markLossEma, 0);
    // resetting will update the last timestamp
    vm.assertEq(markLossLastTs, block.timestamp);

    // Enable various assets
    gtsa.enableAsset(address(markets[MARKET].erc20));
    gtsa.enableAsset(address(markets[MARKET].base));

    // Verify only owner can call admin functions
    vm.startPrank(address(1));
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(1)));
    gtsa.setGTSAParams(0.0002e18, 0.02e18);
  }

  //### Trade Action Tests
  //- Verify successful trade with wrapped deposit asset
  //- Verify successful trade with enabled asset
  //- Verify trade with non-enabled asset fails
  //- Verify trade when EMA mark loss exceeds threshold fails

  //### RFQ Action Tests
  //- Verify valid RFQ action with extraData = 0
  //- Verify valid RFQ action with matching orderHash
  //- Verify RFQ action with mismatched orderHash fails
  //- Verify RFQ action with non-enabled assets fails
  //
  //### Withdrawal Action Tests
  //- Verify withdrawal of wrapped deposit asset
  //- Verify withdrawal of non-wrapped deposit asset fails
  //- Verify withdrawal of non-enabled asset (dust removal scenario)
  //
  //## EMA Logic Tests
  //- Verify EMA calculation with varying time intervals
  //- Test decay factor with different time periods
  //- Verify EMA updates correctly after multiple trades
  //- Test mark loss calculation when share price increases
  //- Test mark loss calculation when share price decreases
  //- Verify action succeeds when EMA loss is below target
  //- Verify action succeeds when current EMA loss <= previous EMA loss (allows recovery)
  //- Verify action fails when EMA loss exceeds target and is increasing
  //
  //## View Function Tests
  //- Verify getAccountValue returns correct values with includePending=true/false
  //- Verify getBasePrice returns correct price from feed
  //- Verify lastSeenHash returns latest action hash
  //- Verify getLBTSAEmaValues returns current EMA state
  //- Verify getLBTSAAddresses returns correct module addresses
}
