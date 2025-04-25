// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IntLib} from "lyra-utils/math/IntLib.sol";
import {FixedPointMathLib} from "lyra-utils/math/FixedPointMathLib.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";
import {Black76} from "lyra-utils/math/Black76.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "lyra-utils/decimals/SignedDecimalMath.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import {BaseTSA} from "./BaseOnChainSigningTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IOptionAsset} from "v2-core/src/interfaces/IOptionAsset.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {IDepositModule} from "../interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../interfaces/IWithdrawalModule.sol";
import {IMatching} from "../interfaces/IMatching.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";

import {
  StandardManager, IStandardManager, IVolFeed, IForwardFeed
} from "v2-core/src/risk-managers/StandardManager.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";
import {EmptyTSA} from "./EmptyTSA.sol";
import {IRfqModule} from "../interfaces/IRfqModule.sol";

/// @title GeneralisedTSA
/// @notice A TSA that allows the owner/signer to trade assets freely, with limited guardrails
/// TODO: EMA using share price instead of mark loss, that way its way more general
contract GeneralisedTSA is EmptyTSA {
  using IntLib for int;
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct GTSAInitParams {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IRfqModule rfqModule;
  }

  /// @custom:storage-location erc7201:lyra.storage.GeneralisedTSA
  struct GTSAStorage {
    ISpotFeed baseFeed;
    IDepositModule depositModule;
    IWithdrawalModule withdrawalModule;
    ITradeModule tradeModule;
    IRfqModule rfqModule;
    /// @dev Only one hash is considered valid at a time, and it is revoked when a new one comes in.
    /// Note: off-chain multiple "atomic" actions can be considered valid at once. Only once they are partially filled
    /// would a new order on-chain invalidate the previous one.
    bytes32 lastSeenHash;
    // EMA
    uint lastSeenSharePrice;
    uint markLossLastTs;
    int markLossEma;
    // EMA params
    uint markLossEmaTarget;
    uint emaDecayFactor;
    // This vault can only actively trade whatever assets are enabled. Cash and deposit asset are always enabled.
    mapping(address => bool) enabledAssets;
  }

  // keccak256(abi.encode(uint256(keccak256("lyra.storage.GeneralisedTSA")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant GENERALISED_TSA_STORAGE_LOCATION =
    0xca73a9a2e8745f9d6c402f73c120b8ce08191d5aebf9cedbfba8c4e5ed90cb00;

  function _getGTSAStorage() internal pure returns (GTSAStorage storage $) {
    assembly {
      $.slot := GENERALISED_TSA_STORAGE_LOCATION
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    BaseTSA.BaseTSAInitParams memory initParams,
    GTSAInitParams memory lbInitParams
  ) external reinitializer(5) {
    __BaseTSA_init(initialOwner, initParams);

    GTSAStorage storage $ = _getGTSAStorage();

    $.baseFeed = lbInitParams.baseFeed;

    $.depositModule = lbInitParams.depositModule;
    $.withdrawalModule = lbInitParams.withdrawalModule;
    $.tradeModule = lbInitParams.tradeModule;
    $.rfqModule = lbInitParams.rfqModule;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.depositAsset.approve(address($.depositModule), type(uint).max);
  }

  ///////////
  // Admin //
  ///////////
  function setLBTSAParams(uint emaDecayFactor, uint markLossEmaTarget) external onlyOwner {
    // Decay factor must be non-zero
    require(emaDecayFactor != 0 && markLossEmaTarget < 0.5e18, GT_InvalidParams());

    GTSAStorage storage $ = _getGTSAStorage();

    $.emaDecayFactor = emaDecayFactor;
    $.markLossEmaTarget = markLossEmaTarget;

    emit GTSAParamsSet(emaDecayFactor, markLossEmaTarget);
  }

  function resetDecay() external onlyOwner {
    GTSAStorage storage $ = _getGTSAStorage();
    $.markLossLastTs = block.timestamp;
    $.markLossEma = 0;
  }

  function enableAsset(address asset) external onlyOwner {
    GTSAStorage storage $ = _getGTSAStorage();
    $.enabledAssets[asset] = true;

    emit AssetEnabled(asset);
  }

  ///////////////////////
  // Action Validation //
  ///////////////////////
  function _verifyAction(IMatching.Action memory action, bytes32 actionHash, bytes memory extraData)
    internal
    virtual
    override
    checkBlocked
  {
    GTSAStorage storage $ = _getGTSAStorage();

    // if the action hash is the same as the last one, we revoke and then re-enable it afterwards (see _signActionData)
    _revokeSignature($.lastSeenHash);
    $.lastSeenHash = actionHash;

    BaseTSAAddresses memory tsaAddresses = getBaseTSAAddresses();

    tsaAddresses.manager.settlePerpsWithIndex(subAccount());

    if (address(action.module) == address($.depositModule)) {
      _verifyDepositAction(action, tsaAddresses);
    } else if (address(action.module) == address($.tradeModule)) {
      _verifyTradeAction(action, tsaAddresses);
    } else if (address(action.module) == address($.rfqModule)) {
      _verifyRfqAction(action, extraData, tsaAddresses);
    } else if (address(action.module) == address($.withdrawalModule)) {
      _verifyWithdrawalAction(action, tsaAddresses);
    } else {
      revert GT_InvalidModule();
    }
  }

  function _verifyTradeAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal {
    GTSAStorage storage $ = _getGTSAStorage();

    ITradeModule.TradeData memory tradeData = abi.decode(action.data, (ITradeModule.TradeData));

    require(
      tradeData.asset == address(tsaAddresses.wrappedDepositAsset) || $.enabledAssets[tradeData.asset],
      GT_InvalidTradeAsset()
    );

    _verifyEmaMarkLoss();
  }

  function _verifyRfqAction(
    IMatching.Action memory action,
    bytes memory extraData,
    BaseTSAAddresses memory tsaAddresses
  ) internal {
    GTSAStorage storage $ = _getGTSAStorage();

    IRfqModule.TradeData[] memory makerTrades;
    if (extraData.length == 0) {
      IRfqModule.RfqOrder memory makerOrder = abi.decode(action.data, (IRfqModule.RfqOrder));
      makerTrades = makerOrder.trades;
    } else {
      IRfqModule.TakerOrder memory takerOrder = abi.decode(action.data, (IRfqModule.TakerOrder));
      if (keccak256(extraData) != takerOrder.orderHash) {
        revert GT_TradeDataDoesNotMatchOrderHash();
      }
      makerTrades = abi.decode(extraData, (IRfqModule.TradeData[]));
    }

    for (uint i = 0; i < makerTrades.length; i++) {
      IRfqModule.TradeData memory makerTrade = makerTrades[i];
      if (makerTrade.asset != address(tsaAddresses.wrappedDepositAsset) || !$.enabledAssets[makerTrade.asset]) {
        revert GT_InvalidTradeAsset();
      }
    }

    _verifyEmaMarkLoss();
  }

  function _verifyWithdrawalAction(IMatching.Action memory action, BaseTSAAddresses memory tsaAddresses) internal view {
    GTSAStorage storage $ = _getGTSAStorage();

    IWithdrawalModule.WithdrawalData memory withdrawData = abi.decode(action.data, (IWithdrawalModule.WithdrawalData));

    require(
      withdrawData.asset == address(tsaAddresses.wrappedDepositAsset)
        || withdrawData.asset != address(tsaAddresses.cash) || !$.enabledAssets[withdrawData.asset], // If the asset is not enabled, we can withdraw it - remove dust
      GT_InvalidWithdrawAsset()
    );

    if (withdrawData.asset != address(tsaAddresses.wrappedDepositAsset)) {
      revert ETSA_InvalidAsset();
    }

    // Note; no restriction to borrow when withdrawing. So a USDC based vault could swap for ETH and then allow
    // withdrawals of USDC (that borrow against the ETH)
  }

  function _verifyEmaMarkLoss() internal {
    GTSAStorage storage $ = _getGTSAStorage();

    uint currentSharePrice = this.getSharesValue(1e18);
    uint lastSharePrice = $.lastSeenSharePrice;

    int markLossPercent = int(currentSharePrice) - int(lastSharePrice);

    int preMarkLossEma = _decayAndFetchEma();
    int emaLoss = preMarkLossEma + markLossPercent;
    $.markLossEma = emaLoss;

    require(emaLoss <= int($.markLossEmaTarget) || emaLoss <= preMarkLossEma, GT_MarkLossTooHigh());
  }

  function _decayAndFetchEma() internal returns (int newEma) {
    GTSAStorage storage $ = _getGTSAStorage();

    uint dt = block.timestamp - $.markLossLastTs;
    uint decay = FixedPointMathLib.exp(-int($.emaDecayFactor * dt));
    $.markLossEma = $.markLossEma.multiplyDecimal(int(decay));
    $.markLossLastTs = block.timestamp;

    return $.markLossEma;
  }

  ///////////////////
  // Account Value //
  ///////////////////

  function _getBasePrice() internal view override returns (uint spotPrice) {
    (spotPrice,) = _getGTSAStorage().baseFeed.getSpot();
  }

  ///////////
  // Views //
  ///////////

  function getAccountValue(bool includePending) public view returns (uint) {
    return _getAccountValue(includePending);
  }

  function getBasePrice() public view returns (uint) {
    return _getBasePrice();
  }

  function lastSeenHash() public view returns (bytes32) {
    return _getGTSAStorage().lastSeenHash;
  }

  function getLBTSAEmaValues() public view returns (int markLossEma, uint markLossLastTs) {
    return (_getGTSAStorage().markLossEma, _getGTSAStorage().markLossLastTs);
  }

  function getLBTSAAddresses()
    public
    view
    returns (ISpotFeed, IDepositModule, IWithdrawalModule, ITradeModule, IRfqModule)
  {
    GTSAStorage storage $ = _getGTSAStorage();
    return ($.baseFeed, $.depositModule, $.withdrawalModule, $.tradeModule, $.rfqModule);
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event GTSAParamsSet(uint emaDecayFactor, uint markLossEmaTarget);
  event AssetEnabled(address indexed asset);

  error GT_TradeDataDoesNotMatchOrderHash();
  error GT_InvalidWithdrawAsset();
  error GT_InvalidTradeAsset();
  error GT_InvalidParams();
  error GT_InvalidModule();
  error GT_MarkLossTooHigh();
}
