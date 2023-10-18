#!/bin/sh

# Gives this account 10000 ethers to start with <3
address=$(cast wallet address "$PRIVATE_KEY")
cast rpc --rpc-url http://localhost:$PORT anvil_setBalance "$address" 0x21e19e0c9bab2400000

# Deploy v2-core repos
cd ./lib/v2-core
forge script scripts/deploy-mocks.s.sol --rpc-url http://localhost:$PORT/ --broadcast
forge script scripts/deploy-core.s.sol --rpc-url http://localhost:$PORT/ --broadcast
MARKET_NAME=weth forge script scripts/deploy-market.s.sol --rpc-url http://localhost:$PORT/ --broadcast
MARKET_NAME=wbtc forge script scripts/deploy-market.s.sol --rpc-url http://localhost:$PORT/ --broadcast

# Deploy matching contracts
cd ../../
# move previous output as input for matching
cp lib/v2-core/deployments/31337/core.json scripts/input/31337/config.json
chmod go+r scripts/input/31337
chmod go+rw deployments/31337/state.txt

# forge build
forge script scripts/deploy-all.s.sol --rpc-url http://localhost:$PORT/ --broadcast

# store output as file
cast rpc --rpc-url http://localhost:$PORT/ anvil_dumpState > deployments/31337/state.txt

