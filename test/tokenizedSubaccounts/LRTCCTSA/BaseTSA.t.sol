/*
TODO: Tests for TSA depositing, withdrawing and fees (BaseTSA)
Deposits:
- deposits are processed sequentially
- depositors get different amounts of shares based on spot price
- deposits are blocked when there is a liquidation
- deposits cannot be processed if already processed
- deposits can be reverted if not processed in time
- cannot be reverted if processed
- deposits cannot be queued if cap is exceeded
- deposits CAN be processed if cap is exceeded
- any deposit will collect fees correctly (before totalSupply is changed)
- deposits will be scaled by the depositScale
- different decimals are handled correctly
- deposits below the minimum are rejected

Withdrawals:
- withdrawals are processed sequentially
- withdrawals are blocked when there is a liquidation
- only shareKeeper can process withdrawals before the withdrawal delay
- withdrawals can be processed by anyone if not processed in time
- cannot be processed if no funds available for withdraw
- can be processed partially if not enough funds available
- withdrawals cannot be processed if already processed
- can have multiple processed in one transaction, will stop once no funds available
- can have multiple processed in one transaction, will stop once withdrawal delay is not met
- withdrawals will be scaled by the withdrawScale
- withdrawals will collect fees correctly (before totalSupply is changed)
- different decimals are handled correctly

Fees:
- no fee is collected if the feeRecipient is the zero address
- no fee is collected if the fee is 0
- fees are collected correctly
- fees are collected correctly when decimals are different
*/