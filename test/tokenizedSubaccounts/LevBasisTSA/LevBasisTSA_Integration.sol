pragma solidity ^0.8.18;

import "../utils/LBTSATestUtils.sol";

contract LevBasisTSA_IntegrationTests is LBTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLBTSA();
    setupLBTSA();
  }

  function testTradingValidation() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    IActionVerifier.Action memory action = _getSpotTradeAction(2e18, 2000e18);

    vm.prank(signer);
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.signActionData(action, "");

    // Open basis position 3 times
    for (uint i = 0; i < 1; i++) {
      console.log("== opening basis position", i);
      // Buy spot
      _tradeSpot(0.2e18, 2000e18);

      // Short perp
      _tradePerp(-0.2e18, 2000e18);
    }

    // Close out positions in reverse
    for (uint i = 0; i < 1; i++) {
      console.log("== closing out position", i);

      // Buy back perp
      _tradePerp(0.2e18, 2000e18);

      // Sell spot
      _tradeSpot(-0.2e18, 2000e18);
    }
  }
}
