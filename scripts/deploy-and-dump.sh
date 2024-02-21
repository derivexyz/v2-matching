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
  forge script scripts/deploy-erc20s.s.sol --rpc-url $ETH_RPC_URL --broadcast
fi

# Deploy core contracts
forge script scripts/deploy-core.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=ETH forge script scripts/deploy-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=BTC forge script scripts/deploy-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=USDT forge script scripts/deploy-base-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=SNX forge script scripts/deploy-srm-option-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
#MARKET_NAME=WSTETH forge script scripts/deploy-base-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast

# Deploy matching contracts
cd ../../
# Copy previous outputs to deployments folder
cp lib/v2-core/deployments/$chainId/core.json deployments/$chainId/core.json
cp lib/v2-core/deployments/$chainId/ETH.json deployments/$chainId/ETH.json
cp lib/v2-core/deployments/$chainId/BTC.json deployments/$chainId/BTC.json
cp lib/v2-core/deployments/$chainId/USDT.json deployments/$chainId/USDT.json
cp lib/v2-core/deployments/$chainId/SNX.json deployments/$chainId/SNX.json
#cp lib/v2-core/deployments/$chainId/SNX.json deployments/$chainId/WSTETH.json
cp lib/v2-core/scripts/input/$chainId/config.json deployments/$chainId/shared.json

# forge build
forge script scripts/deploy-all.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=ETH forge script scripts/add-perp-to-modules.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=BTC forge script scripts/add-perp-to-modules.s.sol --rpc-url $ETH_RPC_URL --broadcast

if [[ "$ETH_RPC_URL" =~ .*local.* ]]; then
  forge script scripts/update-callees.s.sol --rpc-url $ETH_RPC_URL --broadcast

  # store output as file
  cast rpc anvil_dumpState > deployments/$chainId/state.txt
fi

# Output typehashes for convenience
export PYTHONIOENCODING=utf8
matching=$(cat deployments/$chainId/matching.json | python3 -c "import sys, json; print(json.load(sys.stdin)['matching'])")

echo "Matching:" $matching

echo "Matching Action typehash:" $(cast call --rpc-url $ETH_RPC_URL $matching "ACTION_TYPEHASH()")
echo "Domain separator:" $(cast call --rpc-url $ETH_RPC_URL $matching "domainSeparator()")

