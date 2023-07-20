#!/bin/sh

# Start anvil, put in the background but still show all logs
# adding --host flag so it can be exposed to the host machine
anvil --host 0.0.0.0 --port "$PORT" &

# Allow some time for the anvil server to start up
sleep 5

# Set the output directory path
output_dir="/app/output"

# Gives this account 10000 ethers to start with <3
address=$(cast wallet address "$PRIVATE_KEY")
cast rpc --rpc-url http://localhost:"$PORT" anvil_setBalance "$address" 0x21e19e0c9bab2400000

# Deploy v2-core repos
cd ./lib/v2-core
forge script scripts/deploy-mocks.s.sol --rpc-url http://localhost:"$PORT"/ --broadcast
forge script scripts/deploy-core.s.sol --rpc-url http://localhost:"$PORT"/ --broadcast
MARKET_NAME=weth forge script scripts/deploy-market.s.sol --rpc-url http://localhost:"$PORT"/ --broadcast

cp -r /app/lib/v2-core/scripts/input/31337 "$output_dir"
cp -r /app/lib/v2-core/deployments/31337 "$output_dir"

# Grant read permissions to the file
chmod go+r /app/scripts/input/31337

status=$?
if [ $status -ne 0 ]; then
  echo "Failed to run scripts: $status"
  exit $status
fi

# Deploy matching contracts
cd ../../
forge build
forge script scripts/deploy-all.s.sol --rpc-url http://localhost:"$PORT"/ --broadcast

# Copy matching deployment to the output directory
cp -r /app/deployments/31337 "$output_dir"

# Make the output directory accessible from outside the container
chmod -R 777 "$output_dir"

# Keep the container running
while true; do sleep 1; done
