pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Admin
- ✅set TSA params within bounds
- ✅approve Module
- ✅set and revoke share keeper
*/

contract CCTSA_BaseTSA_Admin is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA("weth");
    setupCCTSA();
  }

  function testCanSetTSAParams() public {
    BaseTSA.BaseTSAAddresses memory baseAddresses = tsa.getBaseTSAAddresses();

    assertEq(address(baseAddresses.subAccounts), address(subAccounts));
    assertEq(address(baseAddresses.auction), address(auction));
    assertEq(address(baseAddresses.cash), address(cash));
    assertEq(address(baseAddresses.wrappedDepositAsset), address(markets["weth"].base));
    assertEq(address(baseAddresses.depositAsset), address(markets["weth"].erc20));
    assertEq(address(baseAddresses.manager), address(srm));
    assertEq(address(baseAddresses.matching), address(matching));

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

    vm.expectRevert(BaseTSA.BTSA_ModuleNotPartOfMatching.selector);
    tsa.approveModule(address(alice), type(uint).max);
  }

  function testCanSetShareKeeper() public {
    tsa.setShareKeeper(address(this), true);
    assertTrue(tsa.shareKeeper(address(this)));
    tsa.setShareKeeper(address(this), false);
    assertTrue(!tsa.shareKeeper(address(this)));
  }
}
