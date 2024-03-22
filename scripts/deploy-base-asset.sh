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

# Deploy core contracts
forge script scripts/deploy-base-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast

# Deploy matching contracts
cd ../../
# Copy previous outputs to deployments folder
cp lib/v2-core/deployments/$chainId/WSTETH.json deployments/$chainId/WSTETH.json
cp lib/v2-core/scripts/input/$chainId/config.json deployments/$chainId/shared.json

