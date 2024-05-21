#!/bin/bash

set -e

# TODO: doesnt handle libraries, must be manually added

markets=(
  "ETH"
  "BTC"
  "USDT"
  "SNX"
  "WSTETH"
  "SFP"
  "SOL"
  "DOGE"
)

core_contracts=(
  "auction ./src/liquidation/DutchAuction.sol"
  "cash ./src/assets/CashAsset.sol"
  "dataSubmitter ./src/periphery/OracleDataSubmitter.sol"
  "optionSettlementHelper ./src/periphery/OptionSettlementHelper.sol"
  "perpSettlementHelper ./src/periphery/PerpSettlementHelper.sol"
  "rateModel ./src/assets/InterestRateModel.sol"
  "securityModule ./src/SecurityModule.sol"
  "srm ./src/risk-managers/StandardManager.sol"
  "srmViewer ./src/risk-managers/SRMPortfolioViewer.sol"
  "stableFeed ./src/feeds/LyraSpotFeed.sol"
  "subAccounts ./src/SubAccounts.sol"
)

market_contracts=(
  "base ./src/assets/WrappedERC20Asset.sol"
  "forwardFeed ./src/feeds/LyraForwardFeed.sol"
  "iapFeed ./src/feeds/LyraSpotDiffFeed.sol"
  "ibpFeed ./src/feeds/LyraSpotDiffFeed.sol"
  "option ./src/assets/OptionAsset.sol"
  "perp ./src/assets/PerpAsset.sol"
  "perpFeed ./src/feeds/LyraSpotDiffFeed.sol"
  "pmrm ./src/risk-managers/PMRM.sol"
  "pmrmLib ./src/risk-managers/PMRMLib.sol"
  "pmrmViewer ./src/risk-managers/BasePortfolioViewer.sol"
  "rateFeed ./src/feeds/LyraRateFeedStatic.sol"
  "spotFeed ./src/feeds/LyraSpotFeed.sol"
  "spotFeed ./src/feeds/SFPSpotFeed.sol"
  "volFeed ./src/feeds/LyraVolFeed.sol"
)


matching_contracts=(
  "auctionUtil ./src/periphery/LyraAuctionUtils.sol"
  "deposit ./src/modules/DepositModule.sol"
  "matching ./src/Matching.sol"
  "settlementUtil ./src/periphery/LyraSettlementUtils.sol"
  "subAccountCreator ./src/periphery/SubAccountCreator.sol"
  "trade ./src/modules/TradeModule.sol"
  "transfer ./src/modules/TransferModule.sol"
  "withdrawal ./src/modules/WithdrawalModule.sol"
  "liquidate ./src/modules/LiquidateModule.sol"
  "rfq ./src/modules/RfqModule.sol"
)


################
# V2 contracts #
################
#chainId=901
#explorer=https://explorerl2new-prod-testnet-0eakp60405.t.conduit.xyz/api
chainId=957
explorer="https://explorer.lyra.finance/api"
cd ./lib/v2-core

# Core
echo "Core"

# TODO: handle individual ERC20s nicer
#forge verify-contract --verifier etherscan --verifier-url "https://sepolia-optimism.etherscan.io/api" "0x0b3639A094854796E3b236DB08646ffd21C0B1B2" "./src/l2/LyraERC20.sol:LyraERC20"


for tuple in "${core_contracts[@]}"; do
  name=$(echo "$tuple" | cut -d' ' -f1)
  filepath=$(echo "$tuple" | cut -d' ' -f2)
  filename=$(basename "$filepath")
  contract="${filename%.sol}"
  # shellcheck disable=SC2046
  address=$(cat ../../deployments/${chainId}/core.json | jq -r -c ".$name")
  echo "$address" "$name"
  forge verify-contract --verifier blockscout --verifier-url "$explorer" "${address}" "${filepath}:${contract}"
  # forge verify-contract "${address}" "${filepath}":"${contract}" --show-standard-json-input > ../../verification/"${name}".json
done

for market in "${markets[@]}"; do
  echo $market

  for tuple in "${market_contracts[@]}"; do
    name=$(echo "$tuple" | cut -d' ' -f1)
    filepath=$(echo "$tuple" | cut -d' ' -f2)
    filename=$(basename "$filepath")
    contract="${filename%.sol}"
    # shellcheck disable=SC2046
    address=$(cat ../../deployments/${chainId}/${market}.json | jq -r -c ".$name")
    if [[ "$address" == "" || "$address" = "null" ]]; then
      continue
    fi
    echo "$address" "$name"
    forge verify-contract --verifier blockscout --verifier-url "$explorer" "${address}" "${filepath}:${contract}"
    # forge verify-contract "${address}" "${filepath}":"${contract}" --show-standard-json-input > ../../verification/"${name}".json
  done
done

######################
# Matching contracts #
######################

cd ../..

echo "Matching"

for tuple in "${matching_contracts[@]}"; do
  name=$(echo "$tuple" | cut -d' ' -f1)
  filepath=$(echo "$tuple" | cut -d' ' -f2)
  filename=$(basename "$filepath")
  contract="${filename%.sol}"
  # shellcheck disable=SC2046
  address=$(cat ./deployments/${chainId}/matching.json | jq -r -c ".$name")
  echo "$address" "$name"
  forge verify-contract --verifier blockscout --verifier-url "$explorer" "${address}" "${filepath}:${contract}"
  # forge verify-contract "${address}" "${filepath}":"${contract}" --show-standard-json-input > ./verification/"${name}".json
done
