#!/bin/sh

# exit on any errors
set -e

# get chainId from rpc -> returns in the format "0x1234" -> strip quotations -> convert to decimal
chainId=$(printf "%d" $(cast rpc --rpc-url $ETH_RPC_URL eth_chainId | tr -d '"'))
echo "Chain Id:" $chainId

address=$(cast wallet address "$PRIVATE_KEY")
echo "Deployer address:" $address

# Gives this account 10000 ethers to start with <3
if [[ "$ETH_RPC_URL" =~ .*local.* ]]; then
  echo "Local RPC, minting 10000 ETH"
  cast rpc anvil_setBalance "$address" 0x21e19e0c9bab2400000
  # create a shared.json file with the signer address
  echo "{\"feedSigners\":[\"0x8888058176c2A8C535059605d1AFE2BCab39Fd03\"]}" > deployments/$chainId/shared.json
  # Only deploy mocks for local
  TOKEN_NAME=USDC TICKER=USDC DECIMALS=18 forge script scripts/core/deploy-erc20.s.sol --rpc-url $ETH_RPC_URL --broadcast
  TOKEN_NAME=ETH TICKER=ETH DECIMALS=18 forge script scripts/core/deploy-erc20.s.sol --rpc-url $ETH_RPC_URL --broadcast
  TOKEN_NAME=BTC TICKER=BTC DECIMALS=8 forge script scripts/core/deploy-erc20.s.sol --rpc-url $ETH_RPC_URL --broadcast
  TOKEN_NAME=USDT TICKER=USDT DECIMALS=6 forge script scripts/core/deploy-erc20.s.sol --rpc-url $ETH_RPC_URL --broadcast
  TOKEN_NAME=SNX TICKER=SNX DECIMALS=18 forge script scripts/core/deploy-erc20.s.sol --rpc-url $ETH_RPC_URL --broadcast
  TOKEN_NAME=WSTETH TICKER=WSTETH DECIMALS=18 forge script scripts/core/deploy-erc20.s.sol --rpc-url $ETH_RPC_URL --broadcast
fi

# Deploy core contracts
forge script scripts/core/deploy-core.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=ETH forge script scripts/core/deploy-pmrm-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=BTC forge script scripts/core/deploy-pmrm-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=USDT forge script scripts/core/deploy-base-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=SNX forge script scripts/core/deploy-srm-option-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=WSTETH forge script scripts/core/deploy-base-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
if [[ "$ETH_RPC_URL" =~ .*local.* ]]; then
  forge script scripts/core/deploy-sfp.s.sol --rpc-url $ETH_RPC_URL --broadcast
fi
MARKET_NAME=SFP forge script scripts/core/deploy-base-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=SOL forge script scripts/core/deploy-perp-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=DOGE forge script scripts/core/deploy-perp-only-market.s.sol --rpc-url $ETH_RPC_URL --broadcast


# Deploy matching contracts
forge script scripts/matching/deploy-matching.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=ETH forge script scripts/matching/add-perp-to-modules.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=BTC forge script scripts/matching/add-perp-to-modules.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=SOL forge script scripts/matching/add-perp-to-modules.s.sol --rpc-url $ETH_RPC_URL --broadcast
MARKET_NAME=DOGE forge script scripts/matching/add-perp-to-modules.s.sol --rpc-url $ETH_RPC_URL --broadcast

forge script scripts/tsa/deploy-tsa.s.sol --rpc-url $ETH_RPC_URL --broadcast

if [[ "$ETH_RPC_URL" =~ .*local.* ]]; then
  forge script scripts/core/update-callees.s.sol --rpc-url $ETH_RPC_URL --broadcast

  # store output as file
  cast rpc anvil_dumpState > deployments/$chainId/state.txt
fi

# Output typehashes for convenience
export PYTHONIOENCODING=utf8
matching=$(cat deployments/$chainId/matching.json | python3 -c "import sys, json; print(json.load(sys.stdin)['matching'])")

echo "Matching:" $matching

echo "Matching Action typehash:" $(cast call --rpc-url $ETH_RPC_URL $matching "ACTION_TYPEHASH()")
echo "Domain separator:" $(cast call --rpc-url $ETH_RPC_URL $matching "domainSeparator()")

