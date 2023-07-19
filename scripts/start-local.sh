#!/bin/sh

# Start the first process
anvil --port 8000 &> /dev/null &
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start anvil: $status"
  exit $status
fi

pwd

# Deploy v2-core repos
cd ./lib/v2-core
forge script scripts/deploy-mocks.s.sol --rpc-url http://localhost:8000/ --broadcast
forge script scripts/deploy-core.s.sol --rpc-url http://localhost:8000/ --broadcast 
# MARKET_NAME=weth forge script scripts/deploy-market.s.sol --rpc-url http://localhost:8000/ --broadcast && \

# copy the out put of core deployment as input to matching repo's deployment script
mv /app/lib/v2-core/deployments/31337/core.json /app/scripts/input/31337/config.json
# grant read premissions to the file
chmod go+r /app/scripts/input/31337


status=$?
if [ $status -ne 0 ]; then
  echo "Failed to run scripts: $status"
  exit $status
fi

# Deploy matching contracts
# copy file from lib/v2-core/deployments/{31337}/core.json to scripts/input/{31337}/config.json
cd ../../  && \
forge build && \
forge script scripts/deploy-all.s.sol --rpc-url http://localhost:8000/ --broadcast