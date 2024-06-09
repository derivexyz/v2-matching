# Tokenized SubAccounts

This directory contains the code for the Tokenized SubAccounts (TSA) feature. TSAs are a way to manage assets in an
automated way. Each TSA allows the depositing of an asset (or potentially multiple, not implemented) and logic that
allows for the trading of those assets via the matching contract system.

## Overview

Tokenized SubAccounts is a feature that allows users to manage their assets in an automated way.
Each subaccount can hold a different type of asset, and the assets in each subaccount are tokenized for easy tracking and management.

## Structure

The `tokenizedSubaccounts` directory is organized as follows:

- `CCTSA.sol`: This is an implementation of the TSA, which allows users to deposit any erc20 accepted by lyra protocol, and sell covered calls using it.
- `TSATestUtils.sol`: This contract includes helper functions for writing tests for the `CCTSA` contract.
- `CCTSATest.t.sol`: This file contains tests for the `CCTSA` contract.
