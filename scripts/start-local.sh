#!/bin/sh

# Start the first process
anvil --port 8000 --block-time 1 &> /dev/null &
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start anvil: $status"
  exit $status
fi

# Deploy v2-core repos
cd ./lib/v2-core && \
forge script scripts/deploy-mocks.s.sol --rpc-url http://host.docker.internal:8000/ --broadcast && \
forge script scripts/deploy-core.s.sol --rpc-url http://host.docker.internal:8000/ --broadcast && \
MARKET_NAME=weth forge script scripts/deploy-market.s.sol --rpc-url http://host.docker.internal:8000/ --broadcast

status=$?
if [ $status -ne 0 ]; then
  echo "Failed to run scripts: $status"
  exit $status
fi

# Deploy matching contracts
# copy file from lib/v2-core/deployments/{31337}/core.json to scripts/input/{31337}/config.json
cd ../../ && \
mv ./lib/v2-core/deployments/31337/core.json scripts/input/31337/config.json && \
# deploy contracts
forge build && \
forge script scripts/deploy-all.s.sol --rpc-url http://host.docker.internal:8000/ --broadcast