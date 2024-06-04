pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
TODO: liquidation of subaccount

Admin
- ✅Only the owner can set the LRTCCTSAParams.
- ✅The LRTCCTSAParams are correctly set and retrieved.
- ✅limits on params

Action Validation
- ✅correctly revokes the last seen hash when a new one comes in.
- ✅reverts for invalid modules.

Deposits
- ✅correctly verifies deposit actions.
- ✅reverts for invalid assets.

SubAccount Withdrawals
- ✅correctly verifies withdrawal actions.
- ✅reverts for invalid assets.
- ✅reverts when there are too many short calls.
- ✅reverts when there is negative cash.

Trading
- ✅reverts for invalid assets.
- Spot Buys
  - ✅successfully buys collateral.
  - ✅reverts when buying too much collateral.
  - ✅allows some leniency when buying spot.
  - ✅Cannot trade when limit price too high
- Spot Sells
  - ✅successfully sells collateral.
  - ✅reverts when selling too much collateral.
  - ✅allows for some leniency when selling spot.
  - ✅Cannot trade when limit price too low
- Option Trading
  - ✅can trade options successfully.
  - ✅reverts when selling too many calls.
  - ✅reverts when opening long.
  - ✅reverts when selling put.
  - ✅reverts for expired options.
  - ✅reverts for options with expiry out of bounds.
  - ✅reverts for options with delta too low.
  - ✅reverts for options with price too low.
*/

contract LRTCCTSA_ValidationTests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }

  ///////////
  // Admin //
  ///////////

  function testAdmin() public {
    LRTCCTSA.LRTCCTSAParams memory params = defaultLrtccTSAParams;
    params.feeFactor = 0.05e18;

    // Only the owner can set the LRTCCTSAParams.
    vm.prank(address(10));
    vm.expectRevert();
    tsa.setLRTCCTSAParams(params);

    // The LRTCCTSAParams are correctly set and retrieved.
    tsa.setLRTCCTSAParams(params);
    LRTCCTSA.LRTCCTSAParams memory fetchedParams = tsa.getLRTCCTSAParams();

    assertEq(fetchedParams.feeFactor, 0.05e18);
  }

  function testParamLimits() public {
    // test each boundary one by one
    LRTCCTSA.LRTCCTSAParams memory params = defaultLrtccTSAParams;

    params.minSignatureExpiry = 1 minutes - 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.minSignatureExpiry = defaultLrtccTSAParams.minSignatureExpiry;
    params.maxSignatureExpiry = defaultLrtccTSAParams.minSignatureExpiry - 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.maxSignatureExpiry = defaultLrtccTSAParams.maxSignatureExpiry;
    params.worstSpotBuyPrice = 1e18 - 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.worstSpotBuyPrice = 1.2e18 + 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.worstSpotBuyPrice = defaultLrtccTSAParams.worstSpotBuyPrice;
    params.worstSpotSellPrice = 1e18 + 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.worstSpotSellPrice = 0.8e18 - 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.worstSpotSellPrice = defaultLrtccTSAParams.worstSpotSellPrice;
    params.spotTransactionLeniency = 1e18 - 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.spotTransactionLeniency = 1.2e18 + 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.spotTransactionLeniency = defaultLrtccTSAParams.spotTransactionLeniency;
    params.optionVolSlippageFactor = 1e18 + 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.optionVolSlippageFactor = defaultLrtccTSAParams.optionVolSlippageFactor;
    params.optionMaxDelta = 0.5e18;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.optionMaxDelta = defaultLrtccTSAParams.optionMaxDelta;
    params.optionMaxTimeToExpiry = defaultLrtccTSAParams.optionMinTimeToExpiry - 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.optionMaxTimeToExpiry = defaultLrtccTSAParams.optionMaxTimeToExpiry;
    params.optionMaxNegCash = 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.optionMaxNegCash = defaultLrtccTSAParams.optionMaxNegCash;
    params.feeFactor = 0.05e18 + 1;
    vm.expectRevert(LRTCCTSA.LCCT_InvalidParams.selector);
    tsa.setLRTCCTSAParams(params);

    params.feeFactor = defaultLrtccTSAParams.feeFactor;
    tsa.setLRTCCTSAParams(params);
  }

  /////////////////
  // Base Verify //
  /////////////////
  function testLastActionHashIsRevoked() public {
    // Submit a deposit request
    IActionVerifier.Action memory action1 = _createDepositAction(1e18);

    assertEq(tsa.lastSeenHash(), bytes32(0));

    vm.prank(signer);
    tsa.signActionData(action1);

    assertEq(tsa.lastSeenHash(), tsa.getActionTypedDataHash(action1));

    IActionVerifier.Action memory action2 = _createDepositAction(2e18);

    vm.prank(signer);
    tsa.signActionData(action2);

    assertEq(tsa.lastSeenHash(), tsa.getActionTypedDataHash(action2));

    vm.expectRevert(IActionVerifier.OV_InvalidSignature.selector);
    _submitToMatching(action1);

    // Fails as no funds were actually deposited, but passes signature validation
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    _submitToMatching(action2);
  }

  function testInvalidModules() public {
    vm.startPrank(signer);

    IActionVerifier.Action memory action = _createDepositAction(1e18);
    action.module = IMatchingModule(address(10));

    vm.expectRevert(LRTCCTSA.LCCT_InvalidModule.selector);
    tsa.signActionData(action);

    action.module = depositModule;
    tsa.signActionData(action);
    vm.stopPrank();
  }

  //////////////
  // Deposits //
  //////////////

  function testDepositValidation() public {
    vm.startPrank(signer);

    // correctly verifies deposit actions.
    IActionVerifier.Action memory action = _createDepositAction(1e18);
    tsa.signActionData(action);

    // reverts for invalid assets.
    action.data = _encodeDepositData(1e18, address(11111), address(0));
    vm.expectRevert(LRTCCTSA.LCCT_InvalidAsset.selector);
    tsa.signActionData(action);

    vm.stopPrank();
  }

  /////////////////
  // Withdrawals //
  /////////////////

  function testWithdrawalValidation() public {
    vm.startPrank(signer);

    // correctly verifies withdrawal actions.
    IActionVerifier.Action memory action = _createWithdrawalAction(1e18);
    vm.expectRevert(LRTCCTSA.LCCT_WithdrawingUtilisedCollateral.selector);
    tsa.signActionData(action);

    // reverts for invalid assets.
    action.data = _encodeWithdrawData(1e18, address(11111));
    vm.expectRevert(LRTCCTSA.LCCT_InvalidAsset.selector);
    tsa.signActionData(action);

    vm.stopPrank();
  }

  function testCanWithdrawFromSubaccountSuccessfully() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    // Initiate and process a deposit
    uint depositId = tsa.initiateDeposit(depositAmount, address(this));
    tsa.processDeposit(depositId);

    _executeDeposit(depositAmount);

    (uint sc, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(base, depositAmount);

    _executeWithdrawal(0.5e18);

    (sc, base, cash) = tsa.getSubAccountStats();
    assertEq(base, 0.5e18);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0.5e18);

    // Process a withdrawal of 1
    tsa.requestWithdrawal(1e18);
    tsa.processWithdrawalRequests(1);
    (sc, base, cash) = tsa.getSubAccountStats();
    // 0.5 still in subaccount
    assertEq(base, 0.5e18);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0);

    _executeWithdrawal(0.5e18);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0.5e18);

    tsa.processWithdrawalRequests(1);

    (sc, base, cash) = tsa.getSubAccountStats();
    assertEq(base, 0);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0);
  }

  function testRevertsForInvalidWithdrawals() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    // Initiate and process a deposit
    uint depositId = tsa.initiateDeposit(depositAmount, address(this));
    tsa.processDeposit(depositId);

    uint64 expiry = uint64(block.timestamp + 7 days);
    _executeDeposit(depositAmount);
    _tradeOption(-0.8e18, 100e18, expiry, 2200e18);

    (uint sc, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(base, depositAmount);
    assertEq(sc, 0.8e18);
    assertEq(cash, 80e18);

    IActionVerifier.Action memory action = _createWithdrawalAction(0.3e18);
    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_WithdrawingUtilisedCollateral.selector);
    tsa.signActionData(action);

    // 0.2 can be withdrawn
    _executeWithdrawal(0.2e18);

    // Create negative cash in the account
    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", expiry, 2500e18);
    srm.settleOptions(markets["weth"].option, tsa.subAccount());

    (sc, base, cash) = tsa.getSubAccountStats();
    assertEq(base, 0.8e18);
    assertEq(sc, 0);
    // -300 per option, 0.8 options == -240. +80 cash in account already == -160.
    assertEq(cash, -160e18);

    action = _createWithdrawalAction(0.3e18);
    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_WithdrawalNegativeCash.selector);
    tsa.signActionData(action);
  }

  //////////////////
  // Spot Trading //
  //////////////////

  function testCanBuySpot() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    // Receive positive cash from selling options
    uint64 expiry = uint64(block.timestamp + 7 days);
    _tradeOption(-10e18, 100e18, expiry, 2200e18);

    (uint sc, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(base, 10e18);
    assertEq(sc, 10e18);
    assertEq(cash, 1000e18);

    // Buy 0.3 more base collateral. No fees charged
    _tradeSpot(0.3e18, 2000e18);

    (sc, base, cash) = tsa.getSubAccountStats();

    assertEq(base, 10.3e18);
    assertEq(sc, 10e18);
    assertEq(cash, 400e18);

    // Cant buy more than cash you have
    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address(markets["weth"].base),
      subId: 0,
      limitPrice: int(2000e18),
      desiredAmount: 0.5e18,
      worstFee: 1e18,
      recipientId: tsaSubacc,
      isBid: true
    });

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++signerNonce,
      module: tradeModule,
      data: abi.encode(tradeData),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_BuyingTooMuchCollateral.selector);
    tsa.signActionData(action);

    // fails for limit price too high
    tradeData.desiredAmount = 0.201e18;
    tradeData.limitPrice = int(2500e18);

    action.data = abi.encode(tradeData);
    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_SpotLimitPriceTooHigh.selector);
    tsa.signActionData(action);

    // Can buy more than you have if it is within buffer limit
    _tradeSpot(0.201e18, 2000e18);

    (sc, base, cash) = tsa.getSubAccountStats();

    assertEq(base, 10.501e18);
    assertEq(sc, 10e18);
    // Note cash is now negative from overbuying
    assertEq(cash, -2e18);

    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_MustHavePositiveCash.selector);
    tsa.signActionData(action);
  }

  function testCanSellSpot() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    // Receive positive cash from selling options
    uint64 expiry = uint64(block.timestamp + 7 days);
    _tradeOption(-10e18, 100e18, expiry, 2200e18);

    (uint sc, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(base, 10e18);
    assertEq(sc, 10e18);
    assertEq(cash, 1000e18);

    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", expiry, 2500e18);
    srm.settleOptions(markets["weth"].option, tsa.subAccount());

    (sc, base, cash) = tsa.getSubAccountStats();

    assertEq(sc, 0);
    assertEq(base, 10e18);
    assertEq(cash, -2000e18);

    // Sell 0.5 base collateral
    _tradeSpot(-0.5e18, 2500e18);

    (sc, base, cash) = tsa.getSubAccountStats();
    assertEq(base, 9.5e18);
    assertEq(sc, 0);
    assertEq(cash, -750e18);

    // Cant sell more than you have
    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address(markets["weth"].base),
      subId: 0,
      limitPrice: int(2500e18),
      desiredAmount: 0.5e18,
      worstFee: 1e18,
      recipientId: tsaSubacc,
      isBid: false
    });
    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++signerNonce,
      module: tradeModule,
      data: abi.encode(tradeData),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_SellingTooMuchCollateral.selector);
    tsa.signActionData(action);

    // fails for limit price too high
    tradeData.desiredAmount = 0.301e18;
    tradeData.limitPrice = int(1500e18);
    action.data = abi.encode(tradeData);

    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_SpotLimitPriceTooLow.selector);
    tsa.signActionData(action);

    // Can sell more than you have if it is within buffer limit
    _tradeSpot(-0.301e18, 2500e18);

    (sc, base, cash) = tsa.getSubAccountStats();
    assertEq(base, 9.199e18);
    assertEq(sc, 0);
    // Note: cash went from negative to positive due to buffer
    assertEq(cash, 2.5e18);

    // Fails explicitly when there is a positive cash balance
    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_MustHaveNegativeCash.selector);
    tsa.signActionData(action);
  }

  function testCannotSwapInvalidAssets() public {
    // Cant sell more than you have
    bytes memory tradeData = abi.encode(
      ITradeModule.TradeData({
        asset: address(10),
        subId: 0,
        limitPrice: int(2500e18),
        desiredAmount: 0.5e18,
        worstFee: 1e18,
        recipientId: tsaSubacc,
        isBid: false
      })
    );
    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++signerNonce,
      module: tradeModule,
      data: tradeData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.prank(signer);
    vm.expectRevert(LRTCCTSA.LCCT_InvalidAsset.selector);
    tsa.signActionData(action);
  }

  ////////////////////
  // Option Trading //
  ////////////////////

  function testCanTradeOptions() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    // Receive positive cash from selling options
    uint64 expiry = uint64(block.timestamp + 7 days);
    _tradeOption(-8e18, 100e18, expiry, 2200e18);

    (uint sc, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(base, 10e18);
    assertEq(sc, 8e18);
    assertEq(cash, 800e18);

    ITradeModule.TradeData memory tradeData = ITradeModule.TradeData({
      asset: address(markets["weth"].option),
      subId: OptionEncoding.toSubId(expiry, 2200e18, true),
      limitPrice: int(100e18),
      desiredAmount: 2e18,
      worstFee: 1e18,
      recipientId: tsaSubacc,
      isBid: false
    });

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++signerNonce,
      module: tradeModule,
      data: abi.encode(tradeData),
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.startPrank(signer);

    // Cannot sell more calls than base collateral
    tradeData.desiredAmount = 2.1e18;
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_SellingTooManyCalls.selector);
    tsa.signActionData(action);

    tradeData.desiredAmount = 2.0e18;

    // Can only open short positions
    tradeData.isBid = true;
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_CanOnlyOpenShortOptions.selector);
    tsa.signActionData(action);

    tradeData.isBid = false;

    // Cannot sell puts
    tradeData.subId = OptionEncoding.toSubId(expiry, 2200e18, false);
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_OnlyShortCallsAllowed.selector);
    tsa.signActionData(action);

    tradeData.subId = OptionEncoding.toSubId(expiry, 2200e18, true);
    action.data = abi.encode(tradeData);

    // Cannot trade options with expiry out of bounds
    tradeData.subId =
      OptionEncoding.toSubId(block.timestamp + defaultLrtccTSAParams.optionMinTimeToExpiry - 1, 2200e18, true);
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_OptionExpiryOutOfBounds.selector);
    tsa.signActionData(action);

    tradeData.subId =
      OptionEncoding.toSubId(block.timestamp + defaultLrtccTSAParams.optionMaxTimeToExpiry + 1, 2200e18, true);
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_OptionExpiryOutOfBounds.selector);
    tsa.signActionData(action);

    tradeData.subId = OptionEncoding.toSubId(expiry, 2200e18, true);

    // Cannot trade options with delta too high
    tradeData.subId = OptionEncoding.toSubId(expiry, 2000e18, true);
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_OptionDeltaTooHigh.selector);
    tsa.signActionData(action);

    tradeData.subId = OptionEncoding.toSubId(expiry, 2200e18, true);

    // Cannot trade options with price too low
    tradeData.limitPrice = 5e18;
    action.data = abi.encode(tradeData);
    vm.expectRevert(LRTCCTSA.LCCT_OptionPriceTooLow.selector);
    tsa.signActionData(action);

    // Succeeds
    tradeData.limitPrice = 100e18;
    action.data = abi.encode(tradeData);
    tsa.signActionData(action);

    vm.stopPrank();
  }
}
