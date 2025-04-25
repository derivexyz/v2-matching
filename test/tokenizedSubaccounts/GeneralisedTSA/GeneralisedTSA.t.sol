//# Test Cases for GeneralisedTSA
//
//## Initialization Tests
//- Initialize with valid parameters and verify all modules are set correctly
//- Attempt re-initialization (should fail with reinitializer modifier)
//- Verify deposit asset approval to deposit module after initialization
//
//## Admin Function Tests
//- Set valid EMA parameters (emaDecayFactor > 0, markLossEmaTarget < 0.5e18)
//- Set invalid EMA parameters and verify revert (emaDecayFactor = 0)
//- Set invalid EMA parameters and verify revert (markLossEmaTarget >= 0.5e18)
//- Reset decay parameters and verify markLossLastTs updated to current timestamp
//- Enable various assets and verify they're properly recorded
//- Verify only owner can call admin functions
//
//## Action Verification Tests
//- Test action hash revocation and tracking mechanism
//- Verify perps are settled when any action is verified
//
//### Trade Action Tests
//- Verify successful trade with wrapped deposit asset
//- Verify successful trade with enabled asset
//- Verify trade with non-enabled asset fails
//- Verify trade when EMA mark loss exceeds threshold fails
//
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