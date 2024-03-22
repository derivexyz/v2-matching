# Lyra Matching Contracts 

[![codecov](https://codecov.io/gh/lyra-finance/v2-matching/branch/master/graph/badge.svg?token=ZhHkpl1UGB)](https://codecov.io/gh/lyra-finance/v2-matching)

This repository contains a set of smart contracts designed to enable sequential matching by our back-end on [v2 protocol](https://github.com/lyra-finance/v2-core). The contracts facilitate the execution of transactions based on a trusted keeper (`trade-executor`), while giving user full custody of funds.


## Main components:

`Matching`: Process signed actions and additional "actionData" from the orderbook, ensuring whitelisted modules can execute actions within specified rules. Inherits `ActionVerifier` and `SubAccountManager`

Other Modules: contract that take ownership of user's subAccounts from the matching contract, and then execute accordingly base on what users signed.

For detailed information about the contracts, modules, and installation instructions, please refer to [Notion](https://www.notion.so/lyra-finance/Matching-59db600914334665ba7179c1f03ac6c2).

## Installation:

```shell
git submodule update --init --recursive --force
```

## Building and Testing:

```shell
forge build
```

Run tests

```shell
forge test
```

