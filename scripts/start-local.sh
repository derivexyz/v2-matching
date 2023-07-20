#!/bin/sh

# Start anvil, put in the backend but still showing all logs
# adding --host flag so it can be exposed to the host machine
anvil --host 0.0.0.0 --port 8000 &

# Allow some time for the anvil server to start up
sleep 5

# Set the output directory path
output_dir="/app/output"

# gives this account 10000 ethers to start with <3
address=$(cast wallet address "$PRIVATE_KEY")
cast rpc --rpc-url http://localhost:8000 anvil_setBalance "$address" 0x21e19e0c9bab2400000

# # Deploy v2-core repos
cd ./lib/v2-core
forge script scripts/deploy-mocks.s.sol --rpc-url http://localhost:8000/ --broadcast
forge script scripts/deploy-core.s.sol --rpc-url http://localhost:8000/ --broadcast 
# MARKET_NAME=weth forge script scripts/deploy-market.s.sol --rpc-url http://localhost:8000/ --broadcast && \

# copy the out put of core deployment as input to matching repo's deployment script
# (from lib/v2-core/deployments/{31337}/core.json to scripts/input/{31337}/config.json)
mv /app/lib/v2-core/deployments/31337/core.json /app/scripts/input/31337/config.json
# grant read premissions to the file
chmod go+r /app/scripts/input/31337


status=$?
if [ $status -ne 0 ]; then
  echo "Failed to run scripts: $status"
  exit $status
fi

# Deploy matching contracts
cd ../../  && \
forge build && \
forge script scripts/deploy-all.s.sol --rpc-url http://localhost:8000/ --broadcast

# Copy deployment data to the output directory
cp -r /app/lib/v2-core/deployments/31337 "$output_dir"
cp -r /app/deployments/31337 "$output_dir"
# Move and rename the config.json file to mocks.json
mv /app/scripts/input/31337/config.json "$output_dir/mocks.json"
# Make the output directory accessible from outside the container
chmod -R 777 "$output_dir"

# Keep the container running
while true; do sleep 1; done
