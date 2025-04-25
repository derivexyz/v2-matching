pragma solidity ^0.8.18;

import "../utils/CCTSATestUtils.sol";
import {EmptyTSA} from "src/tokenizedSubaccounts/EmptyTSA.sol";
/*
Account Value
- correctly calculates the account value when there is no ongoing liquidation.
- correctly includes the deposit asset balance in the account value calculation.
- correctly includes the mark-to-market value in the account value calculation.
- correctly converts the mark-to-market value to the base asset's value.
- reverts when the position is insolvent due to a negative mark-to-market value exceeding the deposit asset balance.
- ✅returns zero when there are no assets or liabilities in the account.
- correctly handles the scenario when the mark-to-market value is positive.
- correctly handles the scenario when the mark-to-market value is negative but does not exceed the deposit asset balance.
- account value includes cash interest

Account Stats
- correctly retrieves the number of short calls, base balance, and cash balance.

Base Price
- correctly retrieves the base price.
*/

contract CCTSA_ViewsTests is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA(MARKET);
    setupCCTSA();
  }

  function testAccountValue() public {
    assertEq(cctsa.getAccountValue(false), 0);
    assertEq(cctsa.getAccountValue(true), 0);

    _depositToTSA(1e18);

    assertEq(cctsa.getAccountValue(false), 1e18);
    assertEq(cctsa.getAccountValue(true), 1e18);

    tsa.requestWithdrawal(0.5e18);

    assertEq(cctsa.getAccountValue(false), 1e18);
    assertEq(cctsa.getAccountValue(true), 1e18);

    // changing spot doesnt affect withdrawal amount since there are no options/cash
    _setSpotPrice(MARKET, uint96(MARKET_REF_SPOT * 4 / 5), 1e18);

    tsa.processWithdrawalRequests(1);

    assertEq(cctsa.getAccountValue(false), 0.5e18);
    assertEq(cctsa.getAccountValue(true), 0.5e18);

    _depositToTSA(1.5e18);
    _executeDeposit(2e18);

    uint refTime = block.timestamp;

    _tradeOption(-2e18, 10e18, refTime + 1 weeks, 2600e18);

    (uint sc, uint base, int cash) = cctsa.getSubAccountStats();

    assertEq(sc, 2e18);
    assertEq(base, 2e18);
    assertEq(cash, 20e18);

    // Options are worth more than vault paid, so lost a little bit of value
    assertApproxEqAbs(cctsa.getAccountValue(false), 1.99e18, 0.01e18);

    _depositToTSA(2e18);
    _executeDeposit(2e18);

    // Can have multiple different expiries, as long as valid
    _tradeOption(-1e18, 10e18, refTime + 1 weeks + 1 hours, 2600e18);
    _tradeOption(-1e18, 10e18, refTime + 1 weeks + 2 hours, 2600e18);

    (sc, base, cash) = cctsa.getSubAccountStats();

    assertEq(sc, 4e18);
    assertEq(base, 4e18);
    assertEq(cash, 40e18);

    assertApproxEqAbs(cctsa.getAccountValue(false), 3.99e18, 0.01e18);

    // have to warp so feeds are updated
    vm.warp(block.timestamp + 1);

    // set mtm to be negative (slash base collateral margin and value options highly)
    _setForwardPrice(MARKET, uint64(refTime + 1 weeks), MARKET_REF_SPOT, 1e18);
    _setForwardPrice(MARKET, uint64(refTime + 1 weeks + 1 hours), MARKET_REF_SPOT, 1e18);
    _setForwardPrice(MARKET, uint64(refTime + 1 weeks + 2 hours), MARKET_REF_SPOT, 1e18);

    // value base at 1% for IM
    srm.setBaseAssetMarginFactor(markets[MARKET].id, 0.01e18, 0.01e18);

    (int margin, int mtm) = srm.getMarginAndMarkToMarket(cctsa.subAccount(), true, 0);
    assertLt(margin, 0, "mm: mm < 0 but mtm > 0");
    assertGt(mtm, 0, "mtm: mm < 0 but mtm > 0");

    cctsa.getAccountValue(false);

    // have to warp so feeds are updated
    vm.warp(block.timestamp + 1);

    // but if mtm is < 0 will revert
    // set margin to be negative (slash base collateral margin and value options highly)
    _setForwardPrice(MARKET, uint64(refTime + 1 weeks), MARKET_REF_SPOT * 4, 1e18);
    _setForwardPrice(MARKET, uint64(refTime + 1 weeks + 1 hours), MARKET_REF_SPOT * 4, 1e18);
    _setForwardPrice(MARKET, uint64(refTime + 1 weeks + 2 hours), MARKET_REF_SPOT * 4, 1e18);

    (margin, mtm) = srm.getMarginAndMarkToMarket(cctsa.subAccount(), true, 0);
    assertLt(margin, 0, "mm: mm & mtm < 0");
    assertLt(mtm, 0, "mtm: mm & mtm < 0");

    vm.expectRevert(EmptyTSA.ETSA_PositionInsolvent.selector);
    cctsa.getAccountValue(false);
  }

  function testGetters() public {
    assertEq(cctsa.getBasePrice(), MARKET_REF_SPOT);

    (ISpotFeed sf, IDepositModule dm, IWithdrawalModule wm, ITradeModule tm, IOptionAsset oa) =
      cctsa.getCCTSAAddresses();

    assertEq(address(sf), address(markets[MARKET].spotFeed));
    assertEq(address(dm), address(depositModule));
    assertEq(address(wm), address(withdrawalModule));
    assertEq(address(tm), address(tradeModule));
    assertEq(address(oa), address(markets[MARKET].option));
  }
}
