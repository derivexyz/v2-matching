pragma solidity ^0.8.18;

import "../utils/PPTSATestUtils.sol";

contract PPTSA_ViewsTests is PPTSATestUtils {
  using SafeCast for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToPPTSA(MARKET, true, true);
    setupPPTSA();
  }

  function testPPAccountValue() public {
    assertEq(pptsa.getAccountValue(false), 0);
    assertEq(pptsa.getAccountValue(true), 0);

    _depositToTSA(1e18);

    assertEq(pptsa.getAccountValue(false), 1e18);
    assertEq(pptsa.getAccountValue(true), 1e18);
  }

  function testPPGetters() public {
    _depositToTSA(1e18);
    _executeDeposit(1e18);
    (uint openSpreads, uint base, int cash) = pptsa.getSubAccountStats();
    assertEq(openSpreads, 0);
    assertEq(base, 1e18);
    assertEq(cash, 0);

    assertEq(pptsa.getBasePrice(), MARKET_REF_SPOT);
    assertEq(keccak256(abi.encode(pptsa.getPPTSAParams())), keccak256(abi.encode(defaultPPTSAParams)));
    (ISpotFeed sf, IDepositModule dm, IWithdrawalModule wm, IRfqModule rm, IOptionAsset oa) = pptsa.getPPTSAAddresses();

    assertEq(address(sf), address(markets[MARKET].spotFeed));
    assertEq(address(dm), address(depositModule));
    assertEq(address(wm), address(withdrawalModule));
    assertEq(address(rm), address(rfqModule));
    assertEq(address(oa), address(markets[MARKET].option));
  }
}
