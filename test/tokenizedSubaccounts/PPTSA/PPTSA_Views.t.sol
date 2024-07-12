pragma solidity ^0.8.18;

import "../TSATestUtils.sol";

contract PPTSA_ViewsTests is PPTSATestUtils {
  using SafeCast for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToPPTSA("weth");
    setupPPTSA();
  }

  function testPPAccountValue() public {
    assertEq(tsa.getAccountValue(false), 0);
    assertEq(tsa.getAccountValue(true), 0);

    _depositToTSA(1e18);

    assertEq(tsa.getAccountValue(false), 1e18);
    assertEq(tsa.getAccountValue(true), 1e18);
  }

  function testPPGetters() public {
    _depositToTSA(1e18);
    _executeDeposit(1e18);
    (uint openSpreads, uint base, int cash) = tsa.getSubAccountStats();
    assertEq(openSpreads, 0);
    assertEq(base, 1e18);
    assertEq(cash, 0);

    assertEq(tsa.getBasePrice(), ETH_PRICE.toUint256());
    assertEq(keccak256(abi.encode(tsa.getPPTSAParams())), keccak256(abi.encode(defaultPPTSAParams)));
    (ISpotFeed sf, IDepositModule dm, IWithdrawalModule wm, IRfqModule rm, IOptionAsset oa) = tsa.getPPTSAAddresses();

    assertEq(address(sf), address(markets["weth"].spotFeed));
    assertEq(address(dm), address(depositModule));
    assertEq(address(wm), address(withdrawalModule));
    assertEq(address(rm), address(rfqModule));
    assertEq(address(oa), address(markets["weth"].option));
  }
}
