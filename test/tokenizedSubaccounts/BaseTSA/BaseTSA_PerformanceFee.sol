import "../../../src/tokenizedSubaccounts/BaseTSA.sol";
import "../utils/CCTSATestUtils.sol";

contract CCTSA_BaseTSA_PerformanceFeesTests is CCTSATestUtils {
  address public feeRecipient = address(0xaaafff);

  BaseTSA.TSAParams public defaultPerfTestParams = BaseTSA.TSAParams({
    depositCap: 10000e18,
    minDepositValue: 1e18,
    depositScale: 1e18,
    withdrawScale: 1e18,
    managementFee: 0,
    feeRecipient: feeRecipient,
    performanceFeeWindow: 1 weeks,
    performanceFee: 0.2e18
  });

  function setUp() public override {
    vm.warp(block.timestamp + 1);
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA(MARKET);
    setupCCTSA();

    tsa.setTSAParams(defaultPerfTestParams);
  }

  function testAdminCannotSetInvalidParams() public {
    BaseTSA.TSAParams memory params = defaultPerfTestParams;
    params.performanceFeeWindow = 0;
    vm.expectRevert(BaseTSA.BTSA_InvalidParams.selector);
    tsa.setTSAParams(params);

    params.performanceFeeWindow = defaultPerfTestParams.performanceFeeWindow;
    params.performanceFee = 1e18 + 1;

    vm.expectRevert(BaseTSA.BTSA_InvalidParams.selector);
    tsa.setTSAParams(params);

    params.performanceFee = 1e18;
    tsa.setTSAParams(params);

    vm.assertEq(tsa.getTSAParams().performanceFee, 1e18);
  }

  //## Basic Performance Fee Collection
  //- Test performance fee collection when share price increases within fee window
  //- Test no fee collection when share price decreases within fee window
  //- Test no fee collection when share price remains unchanged

  function testPerformanceFeeCollection() public {
    // Initial deposit to set up the account
    _depositToTSA(1000 * MARKET_UNIT);

    (uint lastFeeCollected, uint perfSnapshotTime, uint perfSnapshotValue) = tsa.getFeeValues();

    vm.assertEq(perfSnapshotTime, block.timestamp);
    vm.assertEq(perfSnapshotValue, 1e18);

    // mint tokens to the TSA directly to simulate positive performance

    markets[MARKET].erc20.mint(address(tsa), 1500 * MARKET_UNIT);

    vm.assertEq(tsa.getSharesValue(1e18), 2.5e18);

    // Collect performance fee
    vm.warp(block.timestamp + 1 weeks);
    tsa.collectFee();

    // profit of 1500, fee of 0.2 * 1500 = $300 of value
    // 300 / 2.5 = 120 shares BUT that doesnt account for dilution
    // correct amount would be ~136.36

    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 136.3636363636e18 * MARKET_UNIT / 1e18, 1e14);

    vm.assertApproxEqAbs(tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 300e18, 1e14);
  }

  function testNoFeeCollectionWhenSharePriceDecreases() public {
    // Initial deposit to set up the account
    _depositToTSA(1000 * MARKET_UNIT);

    (uint lastFeeCollected, uint perfSnapshotTime, uint perfSnapshotValue) = tsa.getFeeValues();

    vm.assertEq(perfSnapshotTime, block.timestamp);
    vm.assertEq(perfSnapshotValue, 1e18);

    // burn tokens from the TSA directly to simulate negative performance
    markets[MARKET].erc20.burn(address(tsa), 500 * MARKET_UNIT);

    vm.assertEq(tsa.getSharesValue(1e18), 0.5e18);

    // Collect performance fee
    vm.warp(block.timestamp + 1 weeks);
    tsa.collectFee();

    // No fee should be collected since share price decreased
    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 0, 1e14);
  }

  function testNoFeeCollectionWhenSharePriceUnchanged() public {
    // Initial deposit to set up the account
    _depositToTSA(1000 * MARKET_UNIT);

    (uint lastFeeCollected, uint perfSnapshotTime, uint perfSnapshotValue) = tsa.getFeeValues();

    vm.assertEq(perfSnapshotTime, block.timestamp);
    vm.assertEq(perfSnapshotValue, 1e18);

    // No change in share price
    vm.assertEq(tsa.getSharesValue(1e18), 1e18);

    // Collect performance fee
    vm.warp(block.timestamp + 1 weeks);
    tsa.collectFee();

    // No fee should be collected since share price remained unchanged
    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 0, 1e14);
  }

  //## Fee Window Behavior
  //- Test performance snapshot reset after fee window elapses
  //- Test multiple fee collection attempts within same window don't collect additional fees
  //- Test snapshot value updates correctly when window passes

  function testFeeWindowModification() public {
    // Initial deposit to set up the account
    _depositToTSA(1000 * MARKET_UNIT);

    (uint lastFeeCollected, uint perfSnapshotTime, uint perfSnapshotValue) = tsa.getFeeValues();

    vm.assertEq(perfSnapshotTime, block.timestamp);
    vm.assertEq(perfSnapshotValue, 1e18);

    vm.warp(block.timestamp + 3 days);

    tsa.collectFee();
    vm.assertEq(tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 0);

    (lastFeeCollected, perfSnapshotTime, perfSnapshotValue) = tsa.getFeeValues();

    vm.assertEq(perfSnapshotTime, block.timestamp - 3 days);
    vm.assertEq(perfSnapshotValue, 1e18);

    // If you skip past the window (+4 days) it will still record current block.timestamp
    vm.warp(block.timestamp + 5 weeks);
    tsa.collectFee();
    vm.assertEq(tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 0);

    (lastFeeCollected, perfSnapshotTime, perfSnapshotValue) = tsa.getFeeValues();
    vm.assertEq(perfSnapshotTime, block.timestamp);

    vm.warp(block.timestamp + 2 days);

    BaseTSA.TSAParams memory params = defaultPerfTestParams;
    params.performanceFeeWindow = 1 days;
    tsa.setTSAParams(params);

    // The perfSnapshotTime doesnt update when params are changed, as they get snapshot BEFORE the change is applied
    (lastFeeCollected, perfSnapshotTime, perfSnapshotValue) = tsa.getFeeValues();
    vm.assertEq(lastFeeCollected, block.timestamp);
    vm.assertEq(perfSnapshotTime, block.timestamp - 2 days);

    // but even 1 second later, you can collect the fee
    vm.warp(block.timestamp + 1);
    tsa.collectFee();
    (lastFeeCollected, perfSnapshotTime, perfSnapshotValue) = tsa.getFeeValues();
    vm.assertEq(lastFeeCollected, block.timestamp);
    vm.assertEq(perfSnapshotTime, block.timestamp);
    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 0, 1e14);

    // The opposite is also true - increasing the window AFTER the old window has passed, will still collect the fee
    vm.warp(block.timestamp + 2 days);
    params.performanceFeeWindow = 1 weeks;
    tsa.setTSAParams(params);

    (lastFeeCollected, perfSnapshotTime, perfSnapshotValue) = tsa.getFeeValues();
    vm.assertEq(lastFeeCollected, block.timestamp);
    vm.assertEq(perfSnapshotTime, block.timestamp);
    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 0, 1e14);
  }

  //## Withdrawal-Specific Performance Fees
  //- Test withdrawal performance fee calculation accuracy
  //- Test partial withdrawal fee calculation
  //- Test withdrawal fees with rising/falling share prices

  function testWithdrawalPerformanceFee() public {
    _depositToTSA(1000 * MARKET_UNIT);
    // +100% pnl
    markets[MARKET].erc20.mint(address(tsa), 1000 * MARKET_UNIT);

    _executeDeposit(2000 * MARKET_UNIT);

    tsa.requestWithdrawal(1000 * MARKET_UNIT);

    // no funds available, so no fee
    tsa.processWithdrawalRequests(1);
    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 0, 1e14);

    /////////

    _executeWithdrawal(100 * MARKET_UNIT);

    // $100 now available for withdraw
    tsa.processWithdrawalRequests(1);

    // 50 shares processed as only $100 available
    // since the fee is $10 on "100", that is 10%
    // 100 / (1 - 0.1) = 111.11 "available"
    // we process $111.11 worth of shares, the value of $100 is paid out to the user, $11.11 to the feeRecipient as
    // shares that are burnt from the user first

    // 55.5555 removed, then 5.5555 added
    vm.assertApproxEqAbs(tsa.getSharesValue(1e18), 2e18, 1e14, "share price still 2");
    vm.assertApproxEqAbs(tsa.totalSupply(), 950e18, 1e14, "feeRecipient shares value");
    vm.assertApproxEqAbs(markets[MARKET].erc20.balanceOf(address(tsa)), 0, 1e14);
    vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 5.55555555e18, 1e14, "feeRecipient shares balance");
    vm.assertApproxEqAbs(
      tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 11.11111111e18, 1e14, "feeRecipient shares value"
    );
    vm.assertApproxEqAbs(
      markets[MARKET].erc20.balanceOf(address(this)), 100 * MARKET_UNIT, 1e14, "feeRecipient shares value"
    );

    /////////

    // snapshot the state, we will try to complete this withdrawal a few different ways
    uint snapshot = vm.snapshot();

    // Case 1 complete withdrawal in full
    {
      // now we withdraw the rest
      _executeWithdrawal(1900 * MARKET_UNIT);
      // we process the rest of the shares
      tsa.processWithdrawalRequests(1);

      // User has 950 - 5.555555 = 944.4444 shares
      // 944.4444 * 2 = 1888.8888
      // performance fee is still 10% of the value
      // so we expect 1888.888 * 0.1 = 188.8888 value to be sent to the feeRecipient
      // 188.8888 / 2 = 94.4444 shares
      // and the user to receive 1888.888 - 188.8888 = 1700.0000
      // So the fee recipient is left with 94.4444 + 5.5555 = 100 shares, worth 200, which is 10% of initial amount

      vm.assertApproxEqAbs(tsa.getSharesValue(1e18), 2e18, 1e14, "share price still 2");
      vm.assertApproxEqAbs(tsa.totalSupply(), 100 * MARKET_UNIT, 1e14, "feeRecipient shares value");
      vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 100 * MARKET_UNIT, 1e14, "feeRecipient shares balance");
      vm.assertApproxEqAbs(
        tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 200 * MARKET_UNIT, 1e14, "feeRecipient shares value"
      );
      vm.assertApproxEqAbs(markets[MARKET].erc20.balanceOf(address(tsa)), 200 * MARKET_UNIT, 1e14);
    }

    vm.revertTo(snapshot);
    snapshot = vm.snapshot();
    // Case 2, gather performance fee normally first, then withdraw remainder with no fee
    {
      vm.warp(block.timestamp + 1 weeks);
      tsa.collectFee();

      // total supply is increased
      // shares are diluted
      // but the fee is still worth 10% of the value, and the user still has the same amount of share value

      vm.assertApproxEqAbs(tsa.getSharesValue(1e18), 1.8e18, 1e14, "2a: share value");
      vm.assertApproxEqAbs(tsa.totalSupply(), 950e18 + 105.55555555e18, 1e14, "2a: totalSupply");
      // fee recipient still only has $200 worth of shares, even though shares are diluted (they have more total shares!)
      vm.assertApproxEqAbs(
        tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 200e18, 1e14, "2a: fee collected share value"
      );

      // now we withdraw the rest
      _executeWithdrawal(1900 * MARKET_UNIT);
      tsa.processWithdrawalRequests(1);

      vm.assertApproxEqAbs(tsa.getSharesValue(1e18), 1.8e18, 1e14, "2b: share price");
      vm.assertApproxEqAbs(tsa.totalSupply(), 111.111111e18, 1e14, "2b: total supply");
      vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 111.111111e18, 1e14, "2b:  feeRecipient shares balance");
      vm.assertApproxEqAbs(
        tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 200e18, 1e14, "2b: feeRecipient shares value"
      );
    }

    vm.revertTo(snapshot);
    // Case 3, gather performance fee normally first, increase Share value, and withdraw partially with fee
    {
      vm.warp(block.timestamp + 1 weeks);
      tsa.collectFee();

      // total supply is increased
      // shares are diluted
      // but the fee is still worth 10% of the value, and the user still has the same amount of share value

      // 1900 in total pool value (including shares minted to fee recipient), so we add 950 to add 50% profit
      markets[MARKET].erc20.mint(address(tsa), 950 * MARKET_UNIT);

      // This increases the value of fees collected already from 200 to 300 (+50%)
      // User is left with 950 shares, worth 1900

      vm.assertApproxEqAbs(tsa.getSharesValue(1e18), 2.7e18, 1e14, "3a: share price");
      vm.assertApproxEqAbs(tsa.totalSupply(), 950e18 + 105.55555555e18, 1e14, "3a: totalSupply");
      // fee recipient still only has $200 worth of shares, even though shares are diluted (they have more total shares!)
      vm.assertApproxEqAbs(
        tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 300e18, 1e14, "3a: fee collected share value"
      );
      vm.assertApproxEqAbs(tsa.queuedWithdrawal(0).amountShares, 944.44444e18, 1e14, "3a: user share amount");
      vm.assertApproxEqAbs(
        tsa.getSharesValue(tsa.queuedWithdrawal(0).amountShares), 2550e18, 1e14, "3a: user share value"
      );

      // now we withdraw the rest (the 950 was not deposited to subaccount)
      _executeWithdrawal(1900 * MARKET_UNIT);
      tsa.processWithdrawalRequests(1);

      vm.assertApproxEqAbs(tsa.getSharesValue(1e18), 2.7e18, 1e14, "3b: share price");
      vm.assertApproxEqAbs(tsa.totalSupply(), 174.074074e18, 1e14, "3b: total supply");
      vm.assertApproxEqAbs(tsa.balanceOf(feeRecipient), 174.074074e18, 1e14, "3b: feeRecipient shares balance");
      vm.assertApproxEqAbs(
        tsa.getSharesValue(tsa.balanceOf(feeRecipient)), 470e18, 1e14, "3b: feeRecipient shares value"
      );
    }
  }
}
