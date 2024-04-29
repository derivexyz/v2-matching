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
)

core_contracts=(
  "subAccounts SubAccounts"
  "cash CashAsset"
  "auction DutchAuction"
  "rateModel InterestRateModel"
  "securityModule SecurityModule"
  "srm StandardManager"
  "srmViewer SRMViewer"
  "stableFeed StableFeed"
  "dataSubmitter OracleDataSubmitter"
  "optionSettlementHelper OptionSettlementHelper"
  "perpSettlementHelper PerpSettlementHelper"
)

market_contracts=(
  "base BaseAsset"
  "option OptionAsset"
  "perp PerpAsset"
  "pmrm PortfolioMarginManager"
  "spotFeed SpotFeed"
  "volFeed VolFeed"
  "forwardFeed ForwardFeed"
  "rateFeed RateFeed(static)"
  "iapFeed PerpImpactAskFeed"
  "ibpFeed PerpImpactBidFeed"
  "perpFeed PerpMidFeed"
  "pmrmLib PMRMLib"
  "pmrmViewer PMRMViewer"
)


matching_contracts=(
  "matching Matching"
  "deposit DepositModule"
  "trade TradeModule"
  "transfer TransferModule"
  "withdrawal WithdrawalModule"
  "liquidate LiquidateModule"
  "rfq RfqModule"
)

periphery_contracts=(
  "subAccountCreator SubAccountCreator"
  "auctionUtil AuctionUtils"
  "settlementUtil LyraSettlementUtils"
)


################
# V2 contracts #
################
echo "# Contracts"

echo "## Bridged ERC20s"

echo "| Contract | Mainnet Address | Testnet Address |"
echo "| --- | --- | --- |"

keys=$(jq 'keys[]' ./deployments/901/shared.json)

for key in $keys; do
  if [[ "$key" == "\"useMockedFeed\"" || "$key" == "\"feedSigners\"" ]]; then
    continue
  fi
  testnet_address=$(cat ./deployments/901/shared.json | jq -r -c ".$key")
  mainnet_address=$(cat ./deployments/957/shared.json | jq -r -c ".$key")
  echo "|" "$(echo $key | tr -d '"')" "|" "$mainnet_address" "|" "$testnet_address" "|"
done


echo ""
echo "## Core"
echo ""

echo "| Contract | Mainnet Address | Testnet Address |"
echo "| --- | --- | --- |"

for tuple in "${core_contracts[@]}"; do
  name=$(echo "$tuple" | cut -d' ' -f1)
  nice_name=$(echo "$tuple" | cut -d' ' -f2)
  testnet_address=$(cat ./deployments/901/core.json | jq -r -c ".$name")
  mainnet_address=$(cat ./deployments/957/core.json | jq -r -c ".$name")
  echo "|" "$nice_name" "|" "$mainnet_address" "|" "$testnet_address" "|"
done

echo ""
echo "## Matching"
echo ""
echo "| Contract | Mainnet Address | Testnet Address |"
echo "| --- | --- | --- |"

for tuple in "${matching_contracts[@]}"; do
  name=$(echo "$tuple" | cut -d' ' -f1)
  nice_name=$(echo "$tuple" | cut -d' ' -f2)
  testnet_address=$(cat ./deployments/901/matching.json | jq -r -c ".$name")
  mainnet_address=$(cat ./deployments/957/matching.json | jq -r -c ".$name")
  echo "|" "$nice_name" "|" "$mainnet_address" "|" "$testnet_address" "|"
done



echo ""
echo "## Currencies"

for market in "${markets[@]}"; do
  echo ""
  if [[ "$market" == "SNX" ]]; then
    echo "### SNX (Inactive)"
  else
    echo "###" $market
  fi
  echo ""
  echo "| Contract | Mainnet Address | Testnet Address |"
  echo "| --- | --- | --- |"

  for tuple in "${market_contracts[@]}"; do
    name=$(echo "$tuple" | cut -d' ' -f1)
    nice_name=$(echo "$tuple" | cut -d' ' -f2)
    testnet_address=$(cat ./deployments/901/${market}.json | jq -r -c ".$name")
    mainnet_address=$(cat ./deployments/957/${market}.json | jq -r -c ".$name")
    if [[ "$testnet_address" = "null" && "$mainnet_address" = "null" ]]; then
      continue
    fi
    echo "|" "$nice_name" "|" "$mainnet_address" "|" "$testnet_address" "|"
  done
done


echo ""
echo "## Periphery"
echo ""
echo "| Contract | Mainnet Address | Testnet Address |"
echo "| --- | --- | --- |"

for tuple in "${periphery_contracts[@]}"; do
  name=$(echo "$tuple" | cut -d' ' -f1)
  nice_name=$(echo "$tuple" | cut -d' ' -f2)
  testnet_address=$(cat ./deployments/901/matching.json | jq -r -c ".$name")
  mainnet_address=$(cat ./deployments/957/matching.json | jq -r -c ".$name")
  echo "|" "$nice_name" "|" "$mainnet_address" "|" "$testnet_address" "|"
done

