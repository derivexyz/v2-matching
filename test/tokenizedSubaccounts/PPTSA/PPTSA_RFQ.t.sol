// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/PPTSATestUtils.sol";
import "forge-std/console2.sol";

import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import {DecimalMath} from "lyra-utils/decimals/DecimalMath.sol";
import "v2-core/src/interfaces/ISubAccounts.sol";

contract PPTSA_ValidationTests is PPTSATestUtils {
  using SignedMath for int;
  using DecimalMath for uint;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth", true, true);
    setupPPTSA();
  }

  function testVerifyRfqParams() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    int amount = 1e18;
    uint price = 1e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint strike = 800e18;
    uint price2 = 4e18;
    uint strike2 = 400e18;
    vm.startPrank(signer);

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, price, expiry, strike, price2, strike2, true);
    IActionVerifier.Action memory action = _createRfqAction(takerOrder);

    takerOrder.orderHash = "";
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeDataDoesNotMatchOrderHash.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // Should fail if the asset is not the option asset
    makerOrder.trades[0].asset = address(markets["weth"].base);
    makerOrder.trades[1].asset = address(markets["weth"].base);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidMakerTradeDetails.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // Should fail when the assets between both legs are not the same
    makerOrder.trades[0].asset = address(markets["weth"].option);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidMakerTradeDetails.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    makerOrder.trades[1].asset = address(markets["weth"].option);

    // Should fail with the wrong length of trades (only 1)
    (IRfqModule.RfqOrder memory smallerMakerOrder,) = _setupRfq(amount, price, expiry, strike, price2, strike2, true);
    IRfqModule.TradeData[] memory smallerTrades = new IRfqModule.TradeData[](1);
    smallerTrades[0] = makerOrder.trades[0];
    smallerMakerOrder.trades = smallerTrades;
    takerOrder.orderHash = keccak256(abi.encode(smallerTrades));
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidTradeLength.selector);
    pptsa.signActionData(action, abi.encode(smallerTrades));

    // Should fail when we're a taker buying long call spreads with a negative high strike amount
    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike2, true);
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike, true);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // Should fail when we're a maker buying long call spreads with a positive high strike amount
    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike, true);
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike2, true);
    action.data = abi.encode(makerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, "");

    // strike difference not matching params
    strike2 = 100e18;
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike2, true);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_StrikePriceOutsideOfDiff.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // trade amounts dont equal each other
    strike2 = 400e18;
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike2, true);
    makerOrder.trades[1].amount = -2e18;
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidTradeAmount.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));
  }

  function testValidateSpreadPriceRanges() public {
    _depositToTSA(100e18);
    _executeDeposit(100e18);
    usdc.mint(address(this), 400_000e6);
    usdc.approve(address(cash), 400_000e6);
    cash.deposit(tsaSubacc, 400_000e6);
    int amount = 100e18;
    uint higherPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    uint lowerPrice = 250e18;
    uint lowStrike = 1600e18;
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;

    // cant buy a long call spread that is too large
    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, true);
    IActionVerifier.Action memory action = _createRfqAction(takerOrder);
    _tradeRfqAsTaker(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, true);
    (uint openSpreads,,) = pptsa.getSubAccountStats();
    assertEq(openSpreads, 100e18);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeTooLarge.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // cant buy a short call spread that is too large
    _setupPPTSAWithDeposit(true, false);
    params.maxTotalCostTolerance = 5e17;
    usdc.mint(address(this), 400_000e6);
    usdc.approve(address(cash), 400_000e6);
    cash.deposit(tsaSubacc, 400_000e6);
    pptsa.setPPTSAParams(params);
    _tradeRfqAsTaker(-1 * amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, true);
    (makerOrder, takerOrder) = _setupRfq(-1 * amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, true);
    action = _createRfqAction(takerOrder);

    (openSpreads,,) = pptsa.getSubAccountStats();
    assertEq(openSpreads, 100e18);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeTooLarge.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // cant buy a long put spread that is too large
    _setupPPTSAWithDeposit(false, true);
    params.maxTotalCostTolerance = 2e18;
    usdc.mint(address(this), 400_000e6);
    usdc.approve(address(cash), 400_000e6);
    cash.deposit(tsaSubacc, 400_000e6);
    pptsa.setPPTSAParams(params);
    _tradeRfqAsTaker(amount, lowerPrice, expiry, lowStrike, higherPrice, highStrike, false);
    (makerOrder, takerOrder) = _setupRfq(amount, lowerPrice, expiry, lowStrike, higherPrice, highStrike, false);
    action = _createRfqAction(takerOrder);

    (openSpreads,,) = pptsa.getSubAccountStats();
    assertEq(openSpreads, 100e18);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeTooLarge.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // cant buy a short put spread that is too large
    _setupPPTSAWithDeposit(false, false);
    params.maxTotalCostTolerance = 5e17;
    usdc.mint(address(this), 400_000e6);
    usdc.approve(address(cash), 400_000e6);
    cash.deposit(tsaSubacc, 400_000e6);
    pptsa.setPPTSAParams(params);
    _tradeRfqAsTaker(-1 * amount, lowerPrice, expiry, lowStrike, higherPrice, highStrike, false);
    (makerOrder, takerOrder) = _setupRfq(-1 * amount, lowerPrice, expiry, lowStrike, higherPrice, highStrike, false);
    action = _createRfqAction(takerOrder);

    (openSpreads,,) = pptsa.getSubAccountStats();
    assertEq(openSpreads, 100e18);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeTooLarge.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));
  }

  function testCostToleranceValidation() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    CollateralManagementTSA.CollateralManagementParams memory collateralManagementParams =
      defaultCollateralManagementParams;
    pptsa.setPPTSAParams(params);
    pptsa.setCollateralManagementParams(collateralManagementParams);
    int amount = 1e18;
    uint price = 411e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint strike = 800e18;
    uint price2 = 4e18;
    uint strike2 = 400e18;

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, price, expiry, strike, price2, strike2, true);

    IActionVerifier.Action memory action = _createRfqAction(takerOrder);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TotalCostOverTolerance.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    params.maxTotalCostTolerance = 1e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    pptsa.setPPTSAParams(params);
    pptsa.setCollateralManagementParams(collateralManagementParams);
  }

  function testShortSpreadCostToleranceValidations() public {
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth", true, false);
    setupPPTSA();
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    CollateralManagementTSA.CollateralManagementParams memory collateralManagementParams =
      defaultCollateralManagementParams;
    pptsa.setPPTSAParams(params);
    pptsa.setCollateralManagementParams(collateralManagementParams);
    int amount = 1e18;
    uint price = 411e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint strike = 800e18;
    uint price2 = 4e18;
    uint strike2 = 400e18;

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, price, expiry, strike, price2, strike2, true);

    IActionVerifier.Action memory action = _createRfqAction(takerOrder);

    price = 300e18;
    (makerOrder, takerOrder) = _setupRfq(amount, price, expiry, strike2, price2, strike, true);
    action.data = abi.encode(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TotalCostBelowTolerance.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    params.maxTotalCostTolerance = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    pptsa.setPPTSAParams(params);
    pptsa.setCollateralManagementParams(collateralManagementParams);

    params.maxTotalCostTolerance = 5e17;
    pptsa.setPPTSAParams(params);
    pptsa.setCollateralManagementParams(collateralManagementParams);
    vm.prank(signer);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    params.maxMarkValueToStrikeDiffRatio = 9e17;
    pptsa.setPPTSAParams(params);
    pptsa.setCollateralManagementParams(collateralManagementParams);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_MarkValueNotWithinBounds.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));
  }

  function testOptionMarkPriceValidations() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    int amount = 1e18;
    uint price = 1e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint strike = 800e18;
    uint price2 = 4e18;
    uint strike2 = 400e18;

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, price, expiry, strike, price2, strike2, true);

    IActionVerifier.Action memory action = _createRfqAction(takerOrder);

    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike, false);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidOptionDetails.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike, true);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    action.data = abi.encode(takerOrder);
    action.expiry = block.timestamp + 8 days + 8 minutes;
    vm.warp(block.timestamp + 8 days);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidOptionDetails.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));
  }

  function testCannotTradeWithTooMuchNegativeCash() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    int amount = 1e18;
    uint lowerPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    uint higherPrice = 151e18;
    uint lowStrike = 1600e18;

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, true);

    IActionVerifier.Action memory action = _createRfqAction(takerOrder);

    // trade so we are just 1 dollar over the negative max cash limit but not too large.
    _tradeRfqAsTaker(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, true);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_CannotTradeWithTooMuchNegativeCash.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));
  }

  function testRFQFeeTooHigh() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    int amount = 1e18;
    uint lowerPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    uint higherPrice = 151e18;
    uint lowStrike = 1600e18;
    _setForwardPrice("weth", uint64(expiry), 2000e18, 1e18);
    _setFixedSVIDataForExpiry("weth", uint64(expiry));
    IRfqModule.TradeData[] memory trades = new IRfqModule.TradeData[](2);
    trades[0] = IRfqModule.TradeData({
      asset: address(markets["weth"].option),
      subId: OptionEncoding.toSubId(expiry, lowStrike, true),
      price: higherPrice,
      amount: amount
    });

    trades[1] = IRfqModule.TradeData({
      asset: address(markets["weth"].option),
      subId: OptionEncoding.toSubId(expiry, highStrike, true),
      price: lowerPrice,
      amount: -amount
    });

    IRfqModule.RfqOrder memory order = IRfqModule.RfqOrder({
      // +1 over expected max possible fee
      maxFee: ((higherPrice - lowerPrice).multiplyDecimal(defaultPPTSAParams.rfqFeeFactor) + 1),
      trades: trades
    });

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(order),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeFeeTooHigh.selector);
    pptsa.signActionData(action, "");
  }

  function testMakerTakerInvalidHighStrikeAmountCombinations() public {
    int amount = 1e18;
    uint higherPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    uint lowerPrice = 250e18;
    uint lowStrike = 1600e18;

    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    _setupPPTSAWithDeposit(true, false);
    params.maxTotalCostTolerance = 5e17;
    pptsa.setPPTSAParams(params);

    // we are the taker buying a short call spread
    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);

    IActionVerifier.Action memory action = _createRfqAction(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // we are the maker buying a short call spread
    makerOrder.trades[0].amount = -amount;
    makerOrder.trades[1].amount = amount;
    action.data = abi.encode(makerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, "");

    _setupPPTSAWithDeposit(true, true);
    params.maxTotalCostTolerance = 2e18;
    pptsa.setPPTSAParams(params);
    // we are a taker buying a long call spread
    (makerOrder, takerOrder) = _setupRfq(-1 * amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    action = _createRfqAction(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // we are the maker buying a long call spread
    makerOrder.trades[0].amount = amount;
    makerOrder.trades[1].amount = -amount;
    action.data = abi.encode(makerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, "");

    _setupPPTSAWithDeposit(false, false);
    params.maxTotalCostTolerance = 5e17;
    pptsa.setPPTSAParams(params);
    // we are the taker buying a short put spread
    (makerOrder, takerOrder) = _setupRfq(-1 * amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, false);
    action = _createRfqAction(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // we are the maker buying a short put spread
    makerOrder.trades[0].amount = amount;
    makerOrder.trades[1].amount = -amount;
    action.data = abi.encode(makerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, "");

    _setupPPTSAWithDeposit(false, true);
    params.maxTotalCostTolerance = 2e18;
    pptsa.setPPTSAParams(params);
    // we are the taker buying a long put spread
    (makerOrder, takerOrder) = _setupRfq(amount, lowerPrice, expiry, highStrike, higherPrice, lowStrike, false);
    action = _createRfqAction(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));

    // we are the maker buying a long put spread
    makerOrder.trades[0].amount = -amount;
    makerOrder.trades[1].amount = amount;
    action.data = abi.encode(makerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    pptsa.signActionData(action, "");
  }

  function testCannotRFQWithIncorrectAmountOfExistingSpreads() public {
    int amount = 1e18;
    uint higherPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    uint lowerPrice = 250e18;
    uint lowStrike = 1600e18;

    _setupPPTSAWithDeposit(true, true);
    _tradeRfqAsMaker(-1 * amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    (uint openSpreads, uint baseBalance, int cashBalance) = pptsa.getSubAccountStats();
    assertEq(openSpreads, amount.abs());
    assertEq(baseBalance, 100e18);
    assertEq(cashBalance, -200e18);

    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: markets["weth"].option, positive: 1e18, negative: 1e18});
    vm.prank(address(subAccounts.manager(nonVaultSubacc)));
    subAccounts.setAssetAllowances(nonVaultSubacc, signer, assetAllowances);

    assetAllowances[0] = IAllowances.AssetAllowance({asset: markets["weth"].option, positive: 1e18, negative: 1e18});
    vm.prank(address(subAccounts.manager(tsaSubacc)));
    subAccounts.setAssetAllowances(tsaSubacc, signer, assetAllowances);

    // transfer some option asset from a non vault account to the vault
    vm.prank(signer);
    ISubAccounts.AssetTransfer memory assetTransfer = ISubAccounts.AssetTransfer({
      asset: markets["weth"].option,
      amount: 0.01e18,
      fromAcc: tsaSubacc,
      toAcc: nonVaultSubacc,
      assetData: bytes32(0),
      subId: OptionEncoding.toSubId(expiry, highStrike, true)
    });
    subAccounts.submitTransfer(assetTransfer, "");

    // now try to trade it will fail
    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    IActionVerifier.Action memory action = _createRfqAction(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidSpreadBalance.selector);
    pptsa.signActionData(action, abi.encode(makerOrder.trades));
  }

  function testCannotChangeStrikeDiffWithOpenSpreads() public {
    int amount = 1e18;
    uint higherPrice = 50e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint highStrike = 2000e18;
    uint lowerPrice = 250e18;
    uint lowStrike = 1600e18;
    _setupPPTSAWithDeposit(true, true);
    _tradeRfqAsMaker(-1 * amount, higherPrice, expiry, highStrike, lowerPrice, lowStrike, true);
    (uint openSpreads,,) = pptsa.getSubAccountStats();
    assertEq(openSpreads, amount.abs());

    defaultPPTSAParams.strikeDiff = 100e18;
    vm.expectRevert(PrincipalProtectedTSA.PPT_CannotChangeStrikeDiffWithOpenSpreads.selector);
    pptsa.setPPTSAParams(defaultPPTSAParams);

    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", expiry, 2500e18);
    srm.settleOptions(markets["weth"].option, pptsa.subAccount());

    pptsa.setPPTSAParams(defaultPPTSAParams);
  }

  function _createRfqAction(IRfqModule.TakerOrder memory takerOrder) internal returns (IActionVerifier.Action memory) {
    return IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });
  }
}
