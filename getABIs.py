import json
import os


matching = {
  "matching": "Matching",
  "deposit": "DepositModule",
  "trade": "TradeModule",
  "transfer": "TransferModule",
  "withdrawal": "WithdrawalModule",
  "subAccountCreator": "SubAccountCreator",
}

core_and_market = {
  "subAccounts": "SubAccounts",
  "rateModel": "InterestRateModel",
  "cash": "CashAsset",
  "securityModule": "SecurityModule",
  "auction": "DutchAuction",
  "srm": "StandardManager",
  "srmViewer": "SRMPortfolioViewer",
  "stableFeed": "ISpotFeed",
  "dataSubmitter": "OracleDataSubmitter",
  "optionSettlementHelper": "OptionSettlementHelper",
  "perpSettlementHelper": "PerpSettlementHelper",
  "option": "OptionAsset",
  "perp": "PerpAsset",
  "base": "WrappedERC20Asset",
  "spotFeed": "LyraSpotFeed",
  "perpFeed": "LyraSpotDiffFeed",
  "iapFeed": "LyraSpotDiffFeed",
  "ibpFeed": "LyraSpotDiffFeed",
  "volFeed": "LyraVolFeed",
  "rateFeed": "LyraRateFeedStatic",
  "forwardFeed": "LyraForwardFeed",
  "pmrm": "PMRM",
  "pmrmLib": "PMRMLib",
  "pmrmViewer": "BasePortfolioViewer"
}


BASE_DIR = os.path.dirname(os.path.realpath(__file__))

for key, value in matching.items():
    print(key, value)
    with open(os.path.join(BASE_DIR, "./out/", value + ".sol/", value + ".json")) as f:
        contents = json.loads(f.read())
        abi = contents["abi"]
    with open(os.path.join(BASE_DIR, "./all_abis/", key + ".json"), "w") as f:
        f.write(json.dumps(abi))

for key, value in core_and_market.items():
    print(key, value)
    with open(os.path.join(BASE_DIR, "./lib/v2-core/out/", value + ".sol/", value + ".json")) as f:
        contents = json.loads(f.read())
        abi = contents["abi"]
    with open(os.path.join(BASE_DIR, "./all_abis/", key + ".json"), "w") as f:
        f.write(json.dumps(abi))



#
# # iterate over all files in the abis directory
# for file in os.listdir(abis_dir):
#     print(file)
#     with open(os.path.join(abis_dir, file)) as f:
#         contents = json.loads(f.read())
#         for row in contents:
#             if row["type"] == "error":
#                 # TODO: need to add args
#                 print(row["name"] + "()", get_selector(row["name"] + "()"))
