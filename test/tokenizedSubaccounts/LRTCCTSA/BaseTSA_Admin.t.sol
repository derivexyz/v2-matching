pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Admin
- ✅set TSA params within bounds
- ✅approve Module
- set and revoke share keeper
*/

contract LRTCCTSA_BaseTSA_Admin is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }

  function testCanSetTSAParams() public {
    BaseTSA.TSAParams memory params = tsa.getTSAParams();

    params.managementFee = 0.02e18 + 1;

    vm.expectRevert(BaseTSA.BTSA_InvalidParams.selector);
    tsa.setTSAParams(params);

    params.managementFee = 0.02e18;
    params.depositScale = 10e18;
    params.withdrawScale = 8e18;

    vm.expectRevert(BaseTSA.BTSA_InvalidParams.selector);
    tsa.setTSAParams(params);

    params.withdrawScale = 12e18;

    vm.expectRevert(BaseTSA.BTSA_InvalidParams.selector);
    tsa.setTSAParams(params);

    params.depositScale = 1;
    params.withdrawScale = 0;

    // division by 0
    vm.expectRevert();
    tsa.setTSAParams(params);

    params.depositScale = 0;
    params.withdrawScale = 1;

    vm.expectRevert(BaseTSA.BTSA_InvalidParams.selector);
    tsa.setTSAParams(params);
  }

  function testCanApproveModule() public {
    tsa.approveModule(address(tradeModule), type(uint).max);
    assertEq(markets["weth"].erc20.allowance(address(tsa), address(tradeModule)), type(uint).max);

    tsa.approveModule(address(tradeModule), 0);
    assertEq(markets["weth"].erc20.allowance(address(tsa), address(tradeModule)), 0);
  }

  function testCanSetShareKeeper() public {
    tsa.setShareKeeper(address(this), true);
    assertTrue(tsa.shareKeeper(address(this)));
    tsa.setShareKeeper(address(this), false);
    assertTrue(!tsa.shareKeeper(address(this)));
  }
}
