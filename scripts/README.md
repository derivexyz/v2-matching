# Deployment

## Deploying to a new network:

1. You must deploy the lyra v2 core contract first. After that, add the following config to the corresponding network id in `scripts/input/{networkId}/config.json`:

```json
{
  "subAccounts": "0xC781643E2df0350C48135b19F9CED36bdf2E1fcF",
  "cashAsset": "0x34eD6a8f990f91Fb8faD8e7AaA6bf6a7E4F4cfA2"
}
```

2. Add the `.env` file with `PRIVATE_KEY` and `TESTNET_RPC_URL` set.

```.env
PRIVATE_KEY=<>

TESTNET_RPC_URL=<>
```

3. Create deployment directory

create the directory in deployments which will be holding the result. Example:

```bash

# create the directory in deployments which will be holding the result
mkdir deployments/901

```

4. Run command

```
forge script scripts/deploy-all.s.sol --rpc-url $TESTNET_RPC_URL --broadcast
```

You should see output similar to this:

```
Start deploying matching contract and modules! deployer:  0x77774066be05E9725cf12A583Ed67F860d19c187
  Written to deployment  /path/deployments/901/matching.json
```

## Getting the raw contract state 

given a private key, we can deploy all needed contracts and dump the state into a file.

```shell
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 PORT=8000 ./scripts/deploy-and-dump.sh
```

This can then be used by other infra to restore the contract state without re-running the deployment script. The output will be in deployments/31337/state.txt
(Make sure to run this against a freshly started anvil node)
