import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "../utils/EGTSATestUtils.sol";

//# Test Cases for EMAGeneralisedTSA

contract EMAGeneralisedTSA_Tests is EGTSATestUtils {
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
        EMAGeneralisedTSA.GTSAInitParams({
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

    gtsa.setGTSAParams(0.002e18, 0.05e18);
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
    vm.expectRevert(EMAGeneralisedTSA.GT_InvalidParams.selector);
    gtsa.setGTSAParams(0, 0.02e18);

    vm.expectRevert(EMAGeneralisedTSA.GT_InvalidParams.selector);
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
  //
  //## EMA Logic Tests
  //- Test mark loss calculation when share price increases
  //- Test mark loss calculation when share price decreases
  //- Verify action succeeds when EMA loss is below target
  //- Verify action succeeds when current EMA loss <= previous EMA loss (allows recovery)
  //- Verify action fails when EMA loss exceeds target and is increasing
  function test_GTSA_tradeActions() external {
    _depositToTSA(100 * MARKET_UNIT);
    _executeDeposit(50 * MARKET_UNIT);
    // Verify successful trade with wrapped deposit asset

    _tradeSpot(-0.2e18, MARKET_REF_SPOT);
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(tsa.subAccount());

    vm.assertEq(assetBalances.length, 2);

    // cannot trade perp until the asset is enabled
    (IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData) =
      _getPerpTradeData(-0.2e18, MARKET_REF_SPOT);

    vm.prank(signer);
    vm.expectRevert(EMAGeneralisedTSA.GT_InvalidTradeAsset.selector);
    tsa.signActionData(actions[0], "");

    // After enabling the asset, can sign the action/execute the trade
    gtsa.enableAsset(address(markets[MARKET].perp));

    vm.prank(signer);
    tsa.signActionData(actions[0], "");

    _verifyAndMatch(actions, signatures, actionData);

    assetBalances = subAccounts.getAccountBalances(tsa.subAccount());
    vm.assertEq(assetBalances.length, 3);

    // Trade will fail if EMA mark loss exceeds threshold

    // Lose about 10% of the vaults value by burning
    markets[MARKET].erc20.burn(address(tsa), 10 * MARKET_UNIT);

    // can just sign the previous action to verify it fails
    vm.prank(signer);
    vm.expectRevert(EMAGeneralisedTSA.GT_MarkLossTooHigh.selector);
    tsa.signActionData(actions[0], "");

    // Check the mark loss
    // doesnt update because the above reverted
    (int markLossEma, uint markLossLastTs) = gtsa.getEmaValues();
    vm.assertEq(markLossEma, 0);

    // but can be prodded to be updated
    gtsa.updateEMA();
    (markLossEma, markLossLastTs) = gtsa.getEmaValues();
    vm.assertEq(markLossEma, 0.1e18);

    // now we can wait to decay this, 0.002 would decay approx 50% every 1hr

    vm.warp(block.timestamp + 1 hours);
    gtsa.updateEMA();
    (markLossEma, markLossLastTs) = gtsa.getEmaValues();
    vm.assertApproxEqRel(markLossEma, 0.05e18, 0.1e18); // within 10%

    // We don't accept "recovery" like we did with mark loss in the LevBasisTSA, since this would be too easily
    // manipulable (updateEMA, donate a tiny amount, trade, repeat...)
    vm.expectRevert(EMAGeneralisedTSA.GT_MarkLossTooHigh.selector);
    vm.prank(signer);
    tsa.signActionData(actions[0], "");

    // since the threshold is 2%, we can trade after 2 more hours! (signature passes)
    vm.warp(block.timestamp + 2 hours);
    vm.prank(signer);
    tsa.signActionData(actions[0], "");
  }

  //### RFQ Action Tests
  //- Verify valid RFQ action with extraData = 0
  //- Verify valid RFQ action with matching orderHash
  //- Verify RFQ action with mismatched orderHash fails
  //- Verify RFQ action with non-enabled assets fails

  function test_GTSA_rfqMaker() external {
    _depositToTSA(100 * MARKET_UNIT);
    _executeDeposit(50 * MARKET_UNIT);

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) = _setupRfq(
      10e18,
      MARKET_REF_SPOT / 10,
      block.timestamp + 1 weeks,
      MARKET_REF_SPOT,
      MARKET_REF_SPOT / 20,
      MARKET_REF_SPOT * 12 / 10,
      true
    );

    (IActionVerifier.Action[] memory actions, bytes[] memory signatures) =
      _getRfqAsMakerSignaturesAndActions(makerOrder, takerOrder);

    vm.prank(signer);
    vm.expectRevert(EMAGeneralisedTSA.GT_InvalidTradeAsset.selector);
    tsa.signActionData(actions[0], "");

    // Enable the asset
    gtsa.enableAsset(address(markets[MARKET].option));

    vm.prank(signer);
    tsa.signActionData(actions[0], "");

    // now verify we can execute the trade

    IRfqModule.FillData memory fill = IRfqModule.FillData({
      makerAccount: tsaSubacc,
      takerAccount: nonVaultSubacc,
      makerFee: 0,
      takerFee: 0,
      managerData: bytes("")
    });

    _verifyAndMatch(actions, signatures, abi.encode(fill));
  }

  function test_GTSA_rfqTaker() external {
    _depositToTSA(100 * MARKET_UNIT);
    _executeDeposit(50 * MARKET_UNIT);

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) = _setupRfq(
      10e18,
      MARKET_REF_SPOT / 10,
      block.timestamp + 1 weeks,
      MARKET_REF_SPOT,
      MARKET_REF_SPOT / 20,
      MARKET_REF_SPOT * 12 / 10,
      true
    );

    IActionVerifier.Action memory takerAction = _createRfqAction(takerOrder);

    vm.prank(signer);
    vm.expectRevert(EMAGeneralisedTSA.GT_InvalidTradeAsset.selector);
    tsa.signActionData(takerAction, abi.encode(makerOrder.trades));

    bytes32 orderHash = takerOrder.orderHash;
    takerOrder.orderHash = bytes32(0);
    takerAction.data = abi.encode(takerOrder);

    vm.prank(signer);
    vm.expectRevert(EMAGeneralisedTSA.GT_TradeDataDoesNotMatchOrderHash.selector);
    tsa.signActionData(takerAction, abi.encode(makerOrder.trades));

    takerOrder.orderHash = orderHash;
    takerAction.data = abi.encode(takerOrder);

    // Enable the asset
    gtsa.enableAsset(address(markets[MARKET].option));

    vm.prank(signer);
    tsa.signActionData(takerAction, abi.encode(makerOrder.trades));
  }

  //
  //### Withdrawal Action Tests
  //- Verify withdrawal of wrapped deposit asset
  //- Verify withdrawal of non-wrapped deposit asset fails
  //- Verify withdrawal of non-enabled asset (dust removal scenario)

  function test_GTSA_withdrawal() public {
    _depositToTSA(100 * MARKET_UNIT);
    _executeDeposit(50 * MARKET_UNIT);

    // Verify withdrawal of wrapped deposit asset
    _executeWithdrawal(50 * MARKET_UNIT);

    // donate to subaccount
    markets[NOT_MARKET].erc20.mint(address(this), 1e18);
    markets[NOT_MARKET].erc20.approve(address(markets[NOT_MARKET].base), type(uint).max);
    markets[NOT_MARKET].base.deposit(tsa.subAccount(), 1e18);

    IActionVerifier.Action memory action = _createWithdrawalAction(0.5e18, address(markets[NOT_MARKET].base));

    vm.prank(signer);
    tsa.signActionData(action, "");

    _submitToMatching(action);

    gtsa.enableAsset(address(markets[NOT_MARKET].base));

    // Verify withdrawal of enabled asset fails
    vm.expectRevert(EMAGeneralisedTSA.GT_InvalidWithdrawAsset.selector);
    vm.prank(signer);
    tsa.signActionData(action, "");
  }
  //## View Function Tests
  //- Verify getAccountValue returns correct values with includePending=true/false
  //- Verify getBasePrice returns correct price from feed
  //- Verify lastSeenHash returns latest action hash
  //- Verify getLBTSAEmaValues returns current EMA state
  //- Verify getLBTSAAddresses returns correct module addresses

  function _createRfqAction(IRfqModule.TakerOrder memory takerOrder) internal returns (IActionVerifier.Action memory) {
    return IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });
  }
}
