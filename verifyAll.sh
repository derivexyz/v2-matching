#!/bin/bash

set -e

# TODO: doesnt handle libraries, must be manually added

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
chainId=957
# https://explorerl2new-prod-testnet-0eakp60405.t.conduit.xyz/api
explorer="https://explorer.lyra.finance/api"
cd ./lib/v2-core

# Core
echo "Core"

# TODO: handle individual ERC20s nicer
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0x954bE1803546150bfd887c9ff70fd221F2F505d3" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xE4e6F3feeAD9C3714F3c9380F91CB56E04F7297E" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xdf77b286eDa539CCb6326e9eDB86aa69D83108a5" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xB696F009e23B31F6a565E187604e43F5B030b241" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xdf77b286eDa539CCb6326e9eDB86aa69D83108a5" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xdf77b286eDa539CCb6326e9eDB86aa69D83108a5" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xdf77b286eDa539CCb6326e9eDB86aa69D83108a5" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xdf77b286eDa539CCb6326e9eDB86aa69D83108a5" "./src/l2/LyraERC20.sol:LyraERC20"
forge verify-contract --verifier blockscout --verifier-url "$explorer" "0xdf77b286eDa539CCb6326e9eDB86aa69D83108a5" "./src/l2/LyraERC20.sol:LyraERC20"
#
#
#for tuple in "${core_contracts[@]}"; do
#  name=$(echo "$tuple" | cut -d' ' -f1)
#  filepath=$(echo "$tuple" | cut -d' ' -f2)
#  filename=$(basename "$filepath")
#  contract="${filename%.sol}"
#  # shellcheck disable=SC2046
#  address=$(cat ../../deployments/${chainId}/core.json | jq -r -c ".$name")
#  echo "$address" "$name"
#  forge verify-contract --verifier blockscout --verifier-url "$explorer" "${address}" "${filepath}:${contract}"
#  # forge verify-contract "${address}" "${filepath}":"${contract}" --show-standard-json-input > ../../verification/"${name}".json
#done
#
## TODO: markets have different sets of contracts
#for market in
#  "ETH"
#  "BTC"
#  "USDT"
#  "SNX"
#; do
#  echo $market
#
#  for tuple in "${market_contracts[@]}"; do
#    name=$(echo "$tuple" | cut -d' ' -f1)
#    filepath=$(echo "$tuple" | cut -d' ' -f2)
#    filename=$(basename "$filepath")
#    contract="${filename%.sol}"
#    # shellcheck disable=SC2046
#    address=$(cat ../../deployments/${chainId}/${market}.json | jq -r -c ".$name")
#    echo "$address" "$name"
#    forge verify-contract --verifier blockscout --verifier-url "$explorer" "${address}" "${filepath}:${contract}"
#    # forge verify-contract "${address}" "${filepath}":"${contract}" --show-standard-json-input > ../../verification/"${name}".json
#  done
#done
#
#######################
## Matching contracts #
#######################
#
#cd ../..
#
#echo "Matching"
#
#for tuple in "${matching_contracts[@]}"; do
#  name=$(echo "$tuple" | cut -d' ' -f1)
#  filepath=$(echo "$tuple" | cut -d' ' -f2)
#  filename=$(basename "$filepath")
#  contract="${filename%.sol}"
#  # shellcheck disable=SC2046
#  address=$(cat ./deployments/${chainId}/matching.json | jq -r -c ".$name")
#  echo "$address" "$name"
#  forge verify-contract --verifier blockscout --verifier-url "$explorer" "${address}" "${filepath}:${contract}"
#  # forge verify-contract "${address}" "${filepath}":"${contract}" --show-standard-json-input > ./verification/"${name}".json
#done
