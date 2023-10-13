// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/Matching.sol";

import {DepositModule, IDepositModule} from "src/modules/DepositModule.sol";
import {WithdrawalModule, IWithdrawalModule} from "src/modules/WithdrawalModule.sol";
import {TransferModule} from "src/modules/TransferModule.sol";
import {TradeModule} from "src/modules/TradeModule.sol";
import {RiskManagerChangeModule} from "src/modules/RiskManagerChangeModule.sol";
import {PMRMTestBase} from "v2-core/test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";
import {IActionVerifier} from "src/interfaces/IActionVerifier.sol";
import {PMRMTestBase} from "v2-core/test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";

import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract MatchingBase is PMRMTestBase {
  // SubAccounts subAccounts;

  Matching public matching;
  DepositModule public depositModule;
  WithdrawalModule public withdrawalModule;
  TransferModule public transferModule;
  TradeModule public tradeModule;
  RiskManagerChangeModule public changeModule;

  // signer
  uint internal camAcc;
  uint internal camPk;
  address internal cam;

  uint internal dougAcc;
  uint internal dougPk;
  address internal doug;

  uint referenceTime;
  uint defaultCallId;

  address tradeExecutor = address(0xaaaa);
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
    defaultCallId = OptionEncoding.toSubId(block.timestamp + 4 weeks, 2000e18, true);

    // Setup matching contract and modules
    matching = new Matching(subAccounts);
    depositModule = new DepositModule(matching);
    withdrawalModule = new WithdrawalModule(matching);
    transferModule = new TransferModule(matching);
    tradeModule = new TradeModule(matching, IAsset(address(cash)), aliceAcc);
    tradeModule.setPerpAsset(IPerpAsset(address(mockPerp)), true);
    changeModule = new RiskManagerChangeModule(matching);

    matching.setAllowedModule(address(depositModule), true);
    matching.setAllowedModule(address(withdrawalModule), true);
    matching.setAllowedModule(address(transferModule), true);
    matching.setAllowedModule(address(tradeModule), true);
    matching.setAllowedModule(address(changeModule), true);

    // console2.log("MATCHIN ADDY:", address(matching));
    // console2.log("DEPOSIT ADDY:", address(depositModule));
    // console2.log("WITHDWL ADDY:", address(withdrawalModule));

    // console2.log("CAM  ADDY:", address(cam));
    // console2.log("DOUG ADDY:", address(doug));
    // console2.log("-------------------------------------------------");

    domainSeparator = matching.domainSeparator();
    matching.setTradeExecutor(tradeExecutor, true);

    _setupAccounts();
    _openCLOBAccount(cam, camAcc);
    _openCLOBAccount(doug, dougAcc);

    _depositCash(camAcc, cashDeposit);
    _depositCash(dougAcc, cashDeposit);
  }

  function _verifyAndMatch(IActionVerifier.Action[] memory actions, bytes[] memory signatures, bytes memory actionData)
    internal
  {
    vm.startPrank(tradeExecutor);
    matching.verifyAndMatch(actions, signatures, actionData);
    vm.stopPrank();
  }

  // Creates SignedAction with empty signature field. This action must be signed for.
  function _createUnsignedAction(
    uint accountId,
    uint nonce,
    address module,
    bytes memory data,
    uint expiry,
    address owner,
    address signer
  ) internal pure returns (IActionVerifier.Action memory action) {
    action = IActionVerifier.Action({
      subaccountId: accountId,
      nonce: nonce,
      module: IMatchingModule(module),
      data: data,
      expiry: expiry,
      owner: owner,
      signer: signer
    });
  }

  function _createActionAndSign(
    uint accountId,
    uint nonce,
    address module,
    bytes memory data,
    uint expiry,
    address owner,
    address signer,
    uint pk
  ) internal view returns (IActionVerifier.Action memory action, bytes memory signature) {
    action = _createUnsignedAction(accountId, nonce, module, data, expiry, owner, signer);
    signature = _signAction(matching.getActionHash(action), pk);
  }

  function _createNewAccount(address owner) internal returns (uint) {
    // create a new account
    uint newAccountId = subAccounts.createAccount(owner, IManager(address(pmrm)));
    vm.startPrank(owner);
    subAccounts.setApprovalForAll(address(matching), true);
    matching.depositSubAccount(newAccountId);
    vm.stopPrank();

    return newAccountId;
  }

  function _getActionHash(IActionVerifier.Action memory action) internal view returns (bytes32) {
    return matching.getActionHash(action);
  }

  function _signAction(bytes32 actionHash, uint signerPk) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, ECDSA.toTypedDataHash(domainSeparator, actionHash));
    return bytes.concat(r, s, bytes1(v));
  }

  function _encodeDepositData(uint amount, address asset, address newManager) internal pure returns (bytes memory) {
    IDepositModule.DepositData memory data =
      IDepositModule.DepositData({amount: amount, asset: asset, managerForNewAccount: newManager});

    return abi.encode(data);
  }

  function _encodeWithdrawData(uint amount, address asset) internal pure returns (bytes memory) {
    IWithdrawalModule.WithdrawalData memory data = IWithdrawalModule.WithdrawalData({asset: asset, assetAmount: amount});

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

  function test() external {
    // to skip coverage
  }
}
