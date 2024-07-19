// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../TSATestUtils.sol";

import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

contract PPTSA_Admin is PPTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth", true, true);
    setupPPTSA();
  }

  // Todo: duplicate of CCTSA validation. Possible merge?
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
}
