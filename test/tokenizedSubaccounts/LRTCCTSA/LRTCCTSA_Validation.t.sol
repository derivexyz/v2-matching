pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Admin
- ✅Only the owner can set the LRTCCTSAParams.
- ✅The LRTCCTSAParams are correctly set and retrieved.
- TODO: limits on params

Action Validation
- ✅correctly revokes the last seen hash when a new one comes in.
- ✅reverts for invalid modules.

Deposits
- correctly verifies deposit actions.
- reverts for invalid assets.

Subaccount Withdrawals
- ✅correctly verifies withdrawal actions.
- ✅reverts for invalid assets.
- ✅reverts when there are too many short calls.
- reverts when there is negative cash.

Trading
- correctly verifies trade actions for buying and selling LRTs and selling options.
- reverts for invalid assets.
- reverts when buying too much collateral.
- reverts when selling too much collateral.
- reverts when selling too many calls.

Option Math
- correctly validates option details.
- reverts for expired options.
- reverts for options with expiry out of bounds.
- reverts for options with delta too low.
- reverts for options with price too low.
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
    // Only the owner can set the LRTCCTSAParams.
    vm.prank(address(10));
    vm.expectRevert();
    tsa.setLRTCCTSAParams(LRTCCTSA.LRTCCTSAParams(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0));

    // The LRTCCTSAParams are correctly set and retrieved.
    tsa.setLRTCCTSAParams(LRTCCTSA.LRTCCTSAParams(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11));
    LRTCCTSA.LRTCCTSAParams memory params = tsa.getLRTCCTSAParams();

    assertEq(params.minSignatureExpiry, 1);
    assertEq(params.maxSignatureExpiry, 2);
    assertEq(params.worstSpotBuyPrice, 3);
    assertEq(params.worstSpotSellPrice, 4);
    assertEq(params.spotTransactionLeniency, 5);
    assertEq(params.optionVolSlippageFactor, 6);
    assertEq(params.optionMaxDelta, 7);
    assertEq(params.optionMinTimeToExpiry, 8);
    assertEq(params.optionMaxTimeToExpiry, 9);
    assertEq(params.optionMaxNegCash, 10);
    assertEq(params.feeFactor, 11);
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

    vm.expectRevert("LRTCCTSA: Invalid module");
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
    vm.expectRevert("LRTCCTSA: Invalid asset");
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
    vm.expectRevert("LRTCCTSA: Cannot withdraw utilised collateral");
    tsa.signActionData(action);

    // reverts for invalid assets.
    action.data = _encodeWithdrawData(1e18, address(11111));
    vm.expectRevert("LRTCCTSA: Invalid asset");
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
    vm.expectRevert("LRTCCTSA: Cannot withdraw utilised collateral");
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
    vm.expectRevert("LRTCCTSA: Cannot withdraw with negative cash");
    tsa.signActionData(action);
  }
}
