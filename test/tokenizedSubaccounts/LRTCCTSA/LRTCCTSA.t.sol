/*
TODO: Tests for LRTCCTSA signing
Admin
- Only the owner can set the LRTCCTSAParams.
- The LRTCCTSAParams are correctly set and retrieved.

Action Validation
- correctly validates deposit, withdrawal, and trade actions.
- correctly revokes the last seen hash when a new one comes in.
- reverts for invalid modules.

Deposits
- correctly verifies deposit actions.
- reverts for invalid assets.

Withdrawals
- correctly verifies withdrawal actions.
- reverts for invalid assets.
- reverts when there are too many short calls.
- reverts when there is negative cash.

Trading
- correctly verifies trade actions for buying and selling LRTs and selling options.
- reverts for invalid assets.
- reverts when buying too much collateral.
- reverts when selling too much collateral.
- reverts when selling too many calls.

Option Math
- correctly validates option details.
- reverts for expired options.
- reverts for options with expiry out of bounds.
- reverts for options with delta too low.
- reverts for options with price too low.

Account Value
- correctly calculates the account value when there is no ongoing liquidation.
- correctly includes the deposit asset balance in the account value calculation.
- correctly includes the mark-to-market value in the account value calculation.
- correctly converts the mark-to-market value to the base asset's value.
- reverts when the position is insolvent due to a negative mark-to-market value exceeding the deposit asset balance.
- returns zero when there are no assets or liabilities in the account.
- correctly handles the scenario when the mark-to-market value is positive.
- correctly handles the scenario when the mark-to-market value is negative but does not exceed the deposit asset balance.

Account Stats
- correctly retrieves the number of short calls, base balance, and cash balance.

Base Price
- correctly retrieves the base price.
*/