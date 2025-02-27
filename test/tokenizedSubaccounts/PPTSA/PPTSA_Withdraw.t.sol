// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/PPTSATestUtils.sol";

import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "v2-core/test/assets/cashAsset/mocks/MockInterestRateModel.sol";

contract PPTSA_ValidationTests is PPTSATestUtils {
  using SignedMath for int;
  using SignedDecimalMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToPPTSA("weth", true, true);
    setupPPTSA();
  }

  function testPPTWithdrawalBaseAssetValidation() public {
    _depositToTSA(3e18);
    vm.startPrank(signer);

    // correctly verifies withdrawal actions.
    IActionVerifier.Action memory action = _createWithdrawalAction(3e18);
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidBaseBalance.selector);
    pptsa.signActionData(action, "");

    // reverts for invalid assets.
    action.data = _encodeWithdrawData(3e18, address(11111));
    vm.expectRevert(PrincipalProtectedTSA.PPT_InvalidAsset.selector);
    pptsa.signActionData(action, "");

    vm.stopPrank();

    // add a trade
    uint expiry = block.timestamp + 1 weeks;
    _executeDeposit(3e18);
    _tradeRfqAsTaker(1e18, 1e18, expiry, 2000e18, 4.0e18, 1600e18, true);

    action = _createWithdrawalAction(3e18);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WithdrawingWithOpenTrades.selector);
    pptsa.signActionData(action, "");

    vm.warp(block.timestamp + 8 days);
    _setSettlementPrice("weth", uint64(expiry), 1500e18);
    srm.settleOptions(markets["weth"].option, pptsa.subAccount());

    vm.startPrank(signer);
    // now try to withdraw all of the base asset. Should fail
    action = _createWithdrawalAction(3e18);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WithdrawingUtilisedCollateral.selector);
    pptsa.signActionData(action, "");

    // now try to a small 5% of the base asset. Should pass
    action = _createWithdrawalAction(0.15e18);
    pptsa.signActionData(action, "");

    vm.stopPrank();
  }

  function testPPTWithdrawAuctionValidations() public {
    // use a mock interest rate model for straightforward interest calcs.
    MockInterestRateModel mockModel = new MockInterestRateModel(0);
    cash.setInterestRateModel(mockModel);
    _depositToTSA(20e18);
    _executeDeposit(20e18);
    auction.setSMAccount(securityModule.accountId());
    // withdraw a large amount of cash so we go insolvent
    vm.prank(subAccounts.ownerOf(tsaSubacc));
    cash.withdraw(tsaSubacc, 10_000e6, address(1234));

    vm.warp(block.timestamp + 1);
    _setSpotPrice("weth", 0, 1e18);
    auction.startAuction(tsaSubacc, 0);

    // cant act while in auction
    IActionVerifier.Action memory action = _createWithdrawalAction(3e18);
    vm.prank(signer);
    vm.expectRevert(BaseTSA.BTSA_Blocked.selector);
    pptsa.signActionData(action, "");

    // clear auction and have half of assets auctioned off
    uint newSubacc = subAccounts.createAccount(address(this), srm);
    usdc.mint(address(this), 1e18);
    usdc.approve(address(cash), 1e18);
    cash.deposit(newSubacc, 1e18);

    auction.bid(tsaSubacc, newSubacc, 0.5e18, 0, 0);

    usdc.mint(address(cash), 1e18);
    cash.disableWithdrawFee();
    vm.warp(block.timestamp + 1);
    _setSpotPrice("weth", 200_000e18, 1e18);
    auction.terminateAuction(tsaSubacc);

    // half of base has been auctioned off, and we still have half negative cash
    int borrowInterestRate = int(mockModel.getBorrowInterestFactor(0, 0));
    (, uint base, int cashBalance) = pptsa.getSubAccountStats();
    assertEq(base, 10e18);
    // dividing by interest rate to ignore interest accrued.
    assertEq(cashBalance.divideDecimal(1e18 + borrowInterestRate), -5_000e18);

    // assert can still do withdrawals, but not too large
    _executeWithdrawal(1e18);
    (, base,) = pptsa.getSubAccountStats();
    assertEq(base, 9e18);

    // try to withdraw too much
    action = _createWithdrawalAction(9e18);
    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_WithdrawingUtilisedCollateral.selector);
    pptsa.signActionData(action, "");
  }

  function testPPTCannotWithdrawWithNegativeBaseBalance() public {
    deployPredeposit(address(usdc));
    upgradeToPPTSA("usdc", true, true);
    PrincipalProtectedTSA ppTSA = PrincipalProtectedTSA(address(proxy));
    setupPPTSA();
    ppTSA.setShareKeeper(address(this), true);

    // send some weth to the tsa to make sure it fail insolvency checks
    vm.prank(address(markets["weth"].base));
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: tsaSubacc,
        asset: markets["weth"].base,
        subId: 0,
        amount: 10e18,
        assetData: bytes32(0)
      }),
      true,
      ""
    );
    vm.prank(address(matching));
    cash.withdraw(tsaSubacc, 1e6, address(1234));
    bytes memory withdrawalData = _encodeWithdrawData(1e18, address(cash));

    IActionVerifier.Action memory action = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: withdrawalModule,
      data: withdrawalData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    vm.prank(signer);
    vm.expectRevert(PrincipalProtectedTSA.PPT_NegativeBaseBalance.selector);
    pptsa.signActionData(action, "");
  }
}
