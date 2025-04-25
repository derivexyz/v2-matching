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
