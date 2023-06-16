// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/Matching.sol";

import {DepositModule} from "src/modules/DepositModule.sol";
import {WithdrawalModule} from "src/modules/WithdrawalModule.sol";
import {TransferModule} from "src/modules/TransferModule.sol";
import {PMRMTestBase} from "v2-core/test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";
import {OrderVerifier} from "src/OrderVerifier.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract MatchingBase is PMRMTestBase {
  // SubAccounts subAccounts;

  Matching matching;
  DepositModule depositModule;
  WithdrawalModule withdrawalModule;
  TransferModule transferModule;
  // signer
  uint internal camAcc;
  uint internal camPk;
  address internal cam;

  uint internal dougAcc;
  uint internal dougPk;
  address internal doug;

  uint referenceTime;

  address tradeExecutor;
  uint cashDeposit = 10000e18;
  bytes32 domainSeparator;

  function setUp() public override {
    super.setUp();

    // Setup signers
    camPk = 0xBEEF;
    cam = vm.addr(camPk);

    dougPk = 0xEEEE;
    doug = vm.addr(dougPk);

    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;

    // Setup matching contract and modules
    matching = new Matching(subAccounts);
    depositModule = new DepositModule(matching);
    withdrawalModule = new WithdrawalModule(matching);
    transferModule = new TransferModule(matching);

    console2.log("MATCHIN ADDY:", address(matching));
    console2.log("DEPOSIT ADDY:", address(depositModule));
    console2.log("WITHDWL ADDY:", address(withdrawalModule));

    console2.log("CAM  ADDY:", address(cam));
    console2.log("DOUG ADDY:", address(doug));
    console2.log("-------------------------------------------------");

    domainSeparator = matching.domainSeparator();
    matching.setTradeExecutor(tradeExecutor, true);

    _setupAccounts();
    _openCLOBAccount(cam, camAcc);
    _openCLOBAccount(doug, dougAcc);

    _depositCash(camAcc, cashDeposit);
    _depositCash(dougAcc, cashDeposit);
  }

  function _verifyAndMatch(OrderVerifier.SignedOrder[] memory orders, bytes memory matchData) internal {
    vm.startPrank(tradeExecutor);
    matching.verifyAndMatch(orders, matchData);
    vm.stopPrank();
  }

  // Creates SignedOrder with empty signature field. This order must be signed for.
  function _createUnsignedOrder(
    uint accountId,
    uint nonce,
    address matcher,
    bytes memory data,
    uint expiry,
    address owner,
    address signer
  ) internal pure returns (OrderVerifier.SignedOrder memory order) {
    order = OrderVerifier.SignedOrder({
      accountId: accountId,
      nonce: nonce,
      matcher: IMatchingModule(matcher),
      data: data,
      expiry: expiry,
      owner: owner,
      signer: signer,
      signature: bytes("")
    });
  }

  // Returns the SignedOrder with signature
  function _createSignedOrder(OrderVerifier.SignedOrder memory unsigned, uint signerPk)
    internal
    view
    returns (OrderVerifier.SignedOrder memory order)
  {
    bytes memory signature = _signOrder(matching.getOrderHash(unsigned), signerPk);

    order = OrderVerifier.SignedOrder({
      accountId: unsigned.accountId,
      nonce: unsigned.nonce,
      matcher: unsigned.matcher,
      data: unsigned.data,
      expiry: unsigned.expiry,
      owner: unsigned.owner,
      signer: unsigned.signer,
      signature: signature
    });
  }

  function _createFullSignedOrder(
    uint accountId,
    uint nonce,
    address matcher,
    bytes memory data,
    uint expiry,
    address owner,
    address signer,
    uint pk
  ) internal view returns (OrderVerifier.SignedOrder memory order) {
    order = _createUnsignedOrder(accountId, nonce, matcher, data, expiry, owner, signer);
    order = _createSignedOrder(order, pk);
  }

  function _getOrderHash(OrderVerifier.SignedOrder memory order) internal view returns (bytes32) {
    return matching.getOrderHash(order);
  }

  function _signOrder(bytes32 orderHash, uint signerPk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, ECDSA.toTypedDataHash(domainSeparator, orderHash));
    return bytes.concat(r, s, bytes1(v));
  }

  function _encodeDepositData(uint amount, address asset, address newManager) internal pure returns (bytes memory) {
    DepositModule.DepositData memory data =
      DepositModule.DepositData({amount: amount, asset: asset, managerForNewAccount: newManager});

    return abi.encode(data);
  }

  function _encodeWithdrawData(uint amount, address asset) internal pure returns (bytes memory) {
    WithdrawalModule.WithdrawalData memory data = WithdrawalModule.WithdrawalData({asset: asset, assetAmount: amount});

    return abi.encode(data);
  }

  function _setupAccounts() internal {
    vm.label(cam, "cam");
    vm.label(doug, "doug");

    camAcc = subAccounts.createAccount(cam, IManager(address(pmrm)));
    dougAcc = subAccounts.createAccount(doug, IManager(address(pmrm)));

    // allow this contract to submit trades
    vm.prank(cam);
    subAccounts.setApprovalForAll(address(this), true);
    vm.prank(doug);
    subAccounts.setApprovalForAll(address(this), true);
  }

  function _openCLOBAccount(address owner, uint accountId) internal {
    vm.startPrank(owner);
    subAccounts.approve(address(matching), accountId);
    matching.depositSubAccount(accountId);
    vm.stopPrank();
  }
}
