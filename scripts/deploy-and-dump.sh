#!/bin/sh

# exit on any errors
set -e

# get chainId from rpc -> returns in the format "0x1234" -> strip quotations -> convert to decimal
chainId=$(printf "%d" $(cast rpc --rpc-url $ETH_RPC_URL eth_chainId | tr -d '"'))
echo "Chain Id:" $chainId

address=$(cast wallet address "$PRIVATE_KEY")
echo "Deployer address:" $address

# Deploy v2-core repos
cd ./lib/v2-core

# Gives this account 10000 ethers to start with <3
if [[ "$ETH_RPC_URL" =~ .*local.* ]]; then
  echo "Local RPC, minting 10000 ETH"
  cast rpc anvil_setBalance "$address" 0x21e19e0c9bab2400000
  # Only deploy mocks for local
  forge script scripts/deploy-mocks.s.sol --rpc-url $ETH_RPC_URL --broadcast
fi

forge script scripts/deploy-core.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=weth forge script scripts/deploy-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=wbtc forge script scripts/deploy-market.s.sol --rpc-url $ETH_RPC_URL --broadcast

# Deploy matching contracts
cd ../../
# Copy previous outputs to deployments folder
cp lib/v2-core/deployments/$chainId/core.json deployments/$chainId/core.json
cp lib/v2-core/deployments/$chainId/weth.json deployments/$chainId/weth.json
cp lib/v2-core/deployments/$chainId/wbtc.json deployments/$chainId/wbtc.json
cp lib/v2-core/scripts/input/$chainId/config.json deployments/$chainId/shared.json

chmod go+r scripts/input/$chainId

# forge build
forge script scripts/deploy-all.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=weth forge script scripts/add-perp-to-trade.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=wbtc forge script scripts/add-perp-to-trade.s.sol --rpc-url $ETH_RPC_URL --broadcast

if [[ "$ETH_RPC_URL" =~ .*local.* ]]; then
  chmod go+rw deployments/$chainId/state.txt
  # store output as file
  cast rpc anvil_dumpState > deployments/$chainId/state.txt
fi
