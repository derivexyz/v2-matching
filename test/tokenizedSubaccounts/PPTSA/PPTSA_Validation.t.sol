// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../TSATestUtils.sol";

import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import "forge-std/console2.sol";

contract PPTSA_ValidationTests is PPTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToPPTSA("weth");
    setupPPTSA();
  }

  function testPPTAdmin() public {
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    params.baseParams.feeFactor = 0.05e18;
    params.minSignatureExpiry = 6 minutes;

    // Only the owner can set the CCTSAParams.
    vm.prank(address(10));
    vm.expectRevert();
    tsa.setPPTSAParams(params);

    // The CCTSAParams are correctly set and retrieved.
    tsa.setPPTSAParams(params);
    assertEq(tsa.getPPTSAParams().baseParams.feeFactor, 0.05e18);
    assertEq(tsa.getPPTSAParams().minSignatureExpiry, 6 minutes);
  }

  function testPPTParamLimits() public {
    // test each boundary one by one
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;

    params.minSignatureExpiry = 1 minutes - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.minSignatureExpiry = defaultPPTSAParams.minSignatureExpiry;
    params.maxSignatureExpiry = defaultPPTSAParams.minSignatureExpiry - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxSignatureExpiry = defaultPPTSAParams.maxSignatureExpiry;
    params.baseParams.worstSpotBuyPrice = 1e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.baseParams.worstSpotBuyPrice = 1.2e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.baseParams.worstSpotBuyPrice = defaultPPTSAParams.baseParams.worstSpotBuyPrice;
    params.baseParams.worstSpotSellPrice = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.baseParams.worstSpotSellPrice = 0.8e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.baseParams.worstSpotSellPrice = defaultPPTSAParams.baseParams.worstSpotSellPrice;
    params.baseParams.spotTransactionLeniency = 1e18 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.baseParams.spotTransactionLeniency = 1.2e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.baseParams.spotTransactionLeniency = defaultPPTSAParams.baseParams.spotTransactionLeniency;
    params.maxTotalCostTolerance = 1e17;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxTotalCostTolerance = defaultPPTSAParams.maxTotalCostTolerance;
    params.maxTotalCostTolerance = 6e18;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxTotalCostTolerance = defaultPPTSAParams.maxTotalCostTolerance;
    params.maxBuyPctOfTVL = 0;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxBuyPctOfTVL = defaultPPTSAParams.maxBuyPctOfTVL;
    params.maxBuyPctOfTVL = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxBuyPctOfTVL = defaultPPTSAParams.maxBuyPctOfTVL;
    params.negMaxCashTolerance = 1e16 - 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.maxBuyPctOfTVL = defaultPPTSAParams.maxBuyPctOfTVL;
    params.negMaxCashTolerance = 1e18 + 1;
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.setPPTSAParams(params);

    params.negMaxCashTolerance = defaultPPTSAParams.negMaxCashTolerance;
    tsa.setPPTSAParams(params);
  }

  /////////////////
  // Base Verify //
  /////////////////

  // Todo: duplicate of CCTSA validation. Possible merge?
  // tests some duplicated code in verify_action
  function testPPTLastActionHashIsRevoked() public {
    _depositToTSA(10e18);

    // Submit a deposit request
    IActionVerifier.Action memory action1 = _createDepositAction(1e18);

    assertEq(tsa.lastSeenHash(), bytes32(0));

    vm.prank(signer);
    tsa.signActionData(action1, "");

    assertEq(tsa.lastSeenHash(), tsa.getActionTypedDataHash(action1));

    IActionVerifier.Action memory action2 = _createDepositAction(2e18);

    vm.prank(signer);
    tsa.signActionData(action2, "");

    assertEq(tsa.lastSeenHash(), tsa.getActionTypedDataHash(action2));

    vm.expectRevert(IActionVerifier.OV_InvalidSignature.selector);
    _submitToMatching(action1);

    // TODO: Can withdraw even with a pending deposit action. Can lead to pending deposits being moved to TSA...
    tsa.requestWithdrawal(10e18);
    tsa.processWithdrawalRequests(1);

    // Fails as no funds were actually deposited, but passes signature validation
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    _submitToMatching(action2);
  }

  // Todo: duplicate of CCTSA validation. Possible merge?
  function testPPTInvalidModules() public {
    _depositToTSA(1e18);

    vm.startPrank(signer);

    IActionVerifier.Action memory action = _createDepositAction(1e18);
    action.module = IMatchingModule(address(10));

    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidModule.selector);
    tsa.signActionData(action, "");

    action.module = depositModule;
    tsa.signActionData(action, "");
    vm.stopPrank();
  }

  /////////////////
  // Withdrawals //
  /////////////////
  function testPPTWithdrawalBaseAssetValidation() public {
    _depositToTSA(3e18);
    vm.startPrank(signer);

    // correctly verifies withdrawal actions.
    IActionVerifier.Action memory action = _createWithdrawalAction(3e18);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidBaseBalance.selector);
    tsa.signActionData(action, "");

    // reverts for invalid assets.
    action.data = _encodeWithdrawData(3e18, address(11111));
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidAsset.selector);
    tsa.signActionData(action, "");

    vm.stopPrank();

    // add a trade
    uint expiry = block.timestamp + 1 weeks;
    _executeDeposit(3e18);
    _tradeRfqAsTaker(1e18, 1e18, expiry, 2000e18, 4.0e18, 1600e18, true);

    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", uint64(expiry), 1500e18);
    srm.settleOptions(markets["weth"].option, tsa.subAccount());

    vm.startPrank(signer);
    // now try to withdraw all of the base asset. Should fail
    action = _createWithdrawalAction(3e18);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WithdrawingUtilisedCollateral.selector);
    tsa.signActionData(action, "");

    // now try to a small 5% of the base asset. Should pass
    action = _createWithdrawalAction(0.15e18);
    tsa.signActionData(action, "");

    vm.stopPrank();
  }

  /////////////////
  //    Trades   //
  /////////////////
  function testTradeValidation() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    // Receive positive cash from selling options
    uint64 expiry = uint64(block.timestamp + 7 days);
    _tradeRfqAsMaker(1e18, 1e18, expiry, 400e18, 4e18, 800e18, true);

    (uint openSpreads, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(openSpreads, 1e18);
    assertEq(base, 10e18);
    assertEq(cash, 3e18);

    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address(markets["weth"].base),
      subId: OptionEncoding.toSubId(expiry, 2200e18, true),
      limitPrice: int(1e18),
      desiredAmount: 2e18,
      worstFee: 1e18,
      recipientId: tsaSubacc,
      isBid: true
    });

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: tradeModule,
      data: abi.encode(tradeData),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.startPrank(signer);

    tradeData.desiredAmount = 0;
    action.data = abi.encode(tradeData);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidDesiredAmount.selector);
    tsa.signActionData(action, "");

    tradeData.desiredAmount = 2.0e18;
    action.module = IMatchingModule(address(10));
    action.data = abi.encode(tradeData);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidModule.selector);
    tsa.signActionData(action, "");

    action.module = tradeModule;
    tradeData.asset = address(markets["weth"].option);
    action.data = abi.encode(tradeData);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidAsset.selector);
    tsa.signActionData(action, "");

    tradeData.asset = address(markets["weth"].base);
    action.data = abi.encode(tradeData);
    tsa.signActionData(action, "");

    vm.warp(block.timestamp + 1 days);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidActionExpiry.selector);
    tsa.signActionData(action, "");
  }

  /////////////////
  //     RFQ     //
  /////////////////
  function testVerifyRfqParams() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    int amount = 1e18;
    uint price = 1e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint strike = 800e18;
    uint pirce2 = 4e18;
    uint strike2 = 400e18;
    vm.startPrank(signer);

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, price, expiry, strike, pirce2, strike2, true);
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    (actions[0], signatures[0]) = _createActionAndSign(
      nonVaultSubacc,
      ++nonVaultNonce,
      address(rfqModule),
      abi.encode(makerOrder),
      block.timestamp + 1 days,
      nonVaultAddr,
      nonVaultAddr,
      nonVaultPk
    );

    actions[1] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    takerOrder.orderHash = "";
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeDataDoesNotMatchOrderHash.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    makerOrder.trades[0].asset = address(markets["weth"].base);
    makerOrder.trades[1].asset = address(markets["weth"].base);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidAsset.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    makerOrder.trades[0].asset = address(markets["weth"].option);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    makerOrder.trades[1].asset = address(markets["weth"].option);

    (IRfqModule.RfqOrder memory smallerMakerOrder,) = _setupRfq(amount, price, expiry, strike, pirce2, strike2, true);
    IRfqModule.TradeData[] memory smallerTrades = new IRfqModule.TradeData[](1);
    smallerTrades[0] = makerOrder.trades[0];
    smallerMakerOrder.trades = smallerTrades;
    takerOrder.orderHash = keccak256(abi.encode(smallerTrades));
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidParams.selector);
    tsa.signActionData(actions[1], abi.encode(smallerTrades));

    // flip strikes
    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike2, true);
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike, true);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike, true);
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike2, true);
    actions[1].data = abi.encode(makerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidHighStrikeAmount.selector);
    tsa.signActionData(actions[1], "");

    // strike too high
    strike2 = 100e18;
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike2, true);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_StrikePriceOutsideOfDiff.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    // trade amounts dont equal
    strike2 = 400e18;
    makerOrder.trades[1].subId = OptionEncoding.toSubId(expiry, strike2, true);
    makerOrder.trades[1].amount = -2e18;
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidTradeAmount.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));
  }

  function testValidateSpreadPriceRanges() public {
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
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    (actions[0], signatures[0]) = _createActionAndSign(
      nonVaultSubacc,
      ++nonVaultNonce,
      address(rfqModule),
      abi.encode(makerOrder),
      block.timestamp + 1 days,
      nonVaultAddr,
      nonVaultAddr,
      nonVaultPk
    );

    actions[1] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    amount = 10e18;
    (makerOrder, takerOrder) = _setupRfq(amount, price, expiry, strike, price2, strike2, true);
    actions[1].data = abi.encode(takerOrder);
    _tradeRfqAsTaker(amount, price, expiry, strike, price2, strike2, true);
    (uint openSpreads,,) = tsa.getSubAccountStats();
    assertEq(openSpreads, 10e18);

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TradeTooLarge.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));
  }

  function testCostToleranceValidation() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);
    PrincipalProtectedTSA.PPTSAParams memory params = defaultPPTSAParams;
    tsa.setPPTSAParams(params);
    int amount = 1e18;
    uint price = 411e18;
    uint64 expiry = uint64(block.timestamp + 7 days);
    uint strike = 800e18;
    uint price2 = 4e18;
    uint strike2 = 400e18;

    (IRfqModule.RfqOrder memory makerOrder, IRfqModule.TakerOrder memory takerOrder) =
      _setupRfq(amount, price, expiry, strike, price2, strike2, true);
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    (actions[0], signatures[0]) = _createActionAndSign(
      nonVaultSubacc,
      ++nonVaultNonce,
      address(rfqModule),
      abi.encode(makerOrder),
      block.timestamp + 1 days,
      nonVaultAddr,
      nonVaultAddr,
      nonVaultPk
    );

    actions[1] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TotalCostOverTolerance.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    params.maxTotalCostTolerance = 1e18 - 1;
    tsa.setPPTSAParams(params);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidCostTolerance.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    params.isLongSpread = false;
    tsa.setPPTSAParams(params);
    price = 300e18;
    (makerOrder, takerOrder) = _setupRfq(amount, price, expiry, strike2, price2, strike, true);
    actions[1].data = abi.encode(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_TotalCostBelowTolerance.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    params.maxTotalCostTolerance = 1e18 + 1;
    tsa.setPPTSAParams(params);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidCostTolerance.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    params.maxTotalCostTolerance = 5e17;
    tsa.setPPTSAParams(params);
    vm.prank(signer);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    params.maxMarkValueToStrikeDiffRatio = 9e17;
    tsa.setPPTSAParams(params);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_MarkValueNotWithinBounds.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));
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
    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    (actions[0], signatures[0]) = _createActionAndSign(
      nonVaultSubacc,
      ++nonVaultNonce,
      address(rfqModule),
      abi.encode(makerOrder),
      block.timestamp + 1 days,
      nonVaultAddr,
      nonVaultAddr,
      nonVaultPk
    );

    actions[1] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: rfqModule,
      data: abi.encode(takerOrder),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike, false);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WrongInputSpread.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));

    makerOrder.trades[0].subId = OptionEncoding.toSubId(expiry, strike, true);
    takerOrder.orderHash = keccak256(abi.encode(makerOrder.trades));
    actions[1].data = abi.encode(takerOrder);
    actions[1].expiry = block.timestamp + 8 days + 8 minutes;
    vm.warp(block.timestamp + 8 days);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_OptionExpired.selector);
    tsa.signActionData(actions[1], abi.encode(makerOrder.trades));
  }
}
