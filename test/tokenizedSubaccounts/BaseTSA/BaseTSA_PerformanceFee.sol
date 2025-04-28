import "../../../src/tokenizedSubaccounts/BaseTSA.sol";
import "../utils/CCTSATestUtils.sol";
//# Performance Fee Test Cases for BaseTSA.sol
//
//## Basic Performance Fee Collection
//- Test performance fee collection when share price increases within fee window
//- Test no fee collection when share price decreases within fee window
//- Test no fee collection when share price remains unchanged
//
//## Fee Window Behavior
//- Test performance snapshot reset after fee window elapses
//- Test multiple fee collection attempts within same window don't collect additional fees
//- Test snapshot value updates correctly when window passes
//
//## Withdrawal-Specific Performance Fees
//- Test withdrawal performance fee calculation accuracy
//- Test partial withdrawal fee calculation
//- Test withdrawal fees with rising/falling share prices
//
//## Parameter Validation
//- Test performanceFee maximum limit enforcement (≤ 100%)
//- Test performanceFeeWindow must be greater than zero
//- Test fee behavior when performanceFee is set to zero
//
//## Edge Cases
//- Test fee collection with zero total supply
//- Test fee recipient being zero address (should not collect fees)
//- Test interaction between management fees and performance fees
//- Test collection at fee window boundaries
//
//## Integration Scenarios
//- Test performance fee calculation after deposits affect share price
//- Test fee collection across multiple performance cycles
//- Test performance fee behavior during market volatility (price up then down)
//- Test correct management of lastPerfSnapshot and lastPerfSnapshotValue state
//
//## Math and Accounting
//- Test correct handling of decimals in performance calculations
//- Test performance fee minting increases totalSupply correctly
//- Test accounting accuracy after fee collection

contract CCTSA_BaseTSA_PerformanceFeesTests is CCTSATestUtils {
  address public feeRecipient = address(0xaaafff);

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA(MARKET);
    setupCCTSA();

    // since fees are initialised as 0, we need to fast forward to enable the performance fee
    vm.warp(block.timestamp + 1);
    tsa.setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000e18,
        minDepositValue: 1e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: feeRecipient,
        performanceFeeWindow: 1 weeks,
        performanceFee: 0.2e18
      })
    );
  }

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
    vm.warp(block.timestamp + 1 weeks + 1);
    tsa.collectFee();

    // profit of 150%, fee of 0.2 * 150% = 30% dilution

    vm.assertEq(tsa.balanceOf(feeRecipient), 300 * MARKET_UNIT);
  }
}
