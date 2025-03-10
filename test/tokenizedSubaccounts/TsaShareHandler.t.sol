// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "./utils/CCTSATestUtils.sol";
import "../../src/tokenizedSubaccounts/TSAShareHandler.sol";

contract MockConnector {
  address public bridge__;
  uint internal messageId;

  constructor(address bridge, uint messageId_) {
    bridge__ = bridge;
    messageId = messageId_;
  }

  function getMinFees(uint msgGasLimit_, uint payloadSize_) external view returns (uint totalFees) {
    return 0.001e18;
  }

  function getMessageId() external view returns (bytes32) {
    return keccak256(abi.encode(messageId));
  }
}

contract MockBridge {
  address public token;

  constructor(address token_) {
    token = token_;
  }

  function bridge(
    address receiver_,
    uint amount_,
    uint msgGasLimit_,
    address connector_,
    bytes calldata execPayload_,
    bytes calldata options_
  ) external payable {
    IERC20(token).transferFrom(msg.sender, address(this), amount_);
  }
}

/// @notice Very rough integration test for CCTSA
contract TSAShareHandlerTest is CCTSATestUtils {
  TSAShareHandler shareHandler;

  address bridgeIn;
  address bridgeOut;

  address connectorIn;
  address connectorOut;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(markets["weth"].erc20));
    upgradeToCCTSA("weth");
    setupCCTSA();

    bridgeIn = address(new MockBridge(address(markets["weth"].erc20)));
    bridgeOut = address(new MockBridge(address(tsa)));

    connectorIn = address(new MockConnector(bridgeIn, 1));
    connectorOut = address(new MockConnector(bridgeOut, 2));

    shareHandler = new TSAShareHandler();
    shareHandler.setKeeper(address(this), true);
  }

  function testCanUseShareHandlerWithoutConnector() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(shareHandler), 10e18);

    // make shares worth 2e18
    _depositToTSA(1e18);
    markets["weth"].erc20.mint(address(tsa), 1e18);

    // BaseTSA toVault, address fallbackDest, address withdrawalConnector, address withdrawalRecipient, uint amount
    shareHandler.initiateDeposit(IBaseTSA(address(tsa)), address(alice), address(0), address(this), 1e18);

    TSAShareHandler.PendingTSAAction[] memory actions = shareHandler.getAllPendingActions();
    assertEq(actions.length, 0);

    actions = shareHandler.getAllUnprocessedActions();
    assertEq(actions.length, 1);

    tsa.processDeposit(actions[0].actionId);
    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 1);
    assertEq(actions[0].amount, 1e18);
    // Ids start from 0, so this is the second deposit
    assertEq(actions[0].actionId, 1);
    assertEq(address(actions[0].vault), address(tsa));
    assertEq(actions[0].fallbackDest, address(alice));
    assertEq(actions[0].withdrawalConnector, address(0));
    assertEq(actions[0].withdrawalRecipient, address(this));

    // only received 0.5 shares
    assertEq(tsa.balanceOf(address(shareHandler)), 0.5e18);

    shareHandler.completeAction(IBaseTSA(address(tsa)), actions[0].actionId);
    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 0);

    // only received 0.5 shares
    assertEq(tsa.balanceOf(address(alice)), 0.5e18);

    actions = shareHandler.getAllUserActions(alice);
    assertEq(actions.length, 1);
    assertEq(actions[0].amount, 1e18);
    assertEq(address(actions[0].vault), address(tsa));
    assertEq(actions[0].fallbackDest, address(alice));
    assertEq(actions[0].withdrawalConnector, address(0));
    assertEq(actions[0].withdrawalRecipient, address(this));
    // only received 0.5 shares
    assertEq(actions[0].amountReceived, 0.5e18);
    assertEq(actions[0].messageId, bytes32(0));

    // Now withdraw
    vm.startPrank(alice);
    tsa.approve(address(shareHandler), 1000e18);
    shareHandler.initiateWithdrawal(IBaseTSA(address(tsa)), address(alice), address(0), address(this), 0.5e18);
    vm.stopPrank();

    actions = shareHandler.getAllUnprocessedActions();
    assertEq(actions.length, 1);

    actions = shareHandler.getAllPendingActions();
    assertEq(actions.length, 0);

    tsa.processWithdrawalRequests(1);

    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 1);
    assertEq(actions[0].amount, 0.5e18);
    // ids start from 0
    assertEq(actions[0].actionId, (0 | (1 << 255)));
    assertEq(address(actions[0].vault), address(tsa));
    assertEq(actions[0].fallbackDest, address(alice));
    assertEq(actions[0].withdrawalConnector, address(0));
    assertEq(actions[0].withdrawalRecipient, address(this));

    assertEq(markets["weth"].erc20.balanceOf(address(shareHandler)), 1e18);

    shareHandler.completeAction(IBaseTSA(address(tsa)), actions[0].actionId);

    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 0);
    assertEq(tsa.balanceOf(address(alice)), 0);
    assertEq(tsa.balanceOf(address(shareHandler)), 0);
    assertEq(markets["weth"].erc20.balanceOf(address(alice)), 1e18);
  }

  function testCanUseShareHandlerWithConnector() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(shareHandler), 10e18);

    // make shares worth 2e18
    _depositToTSA(1e18);
    markets["weth"].erc20.mint(address(tsa), 1e18);

    // BaseTSA toVault, address fallbackDest, address withdrawalConnector, address withdrawalRecipient, uint amount
    shareHandler.initiateDeposit(IBaseTSA(address(tsa)), address(alice), address(connectorOut), address(this), 1e18);

    TSAShareHandler.PendingTSAAction[] memory actions = shareHandler.getAllPendingActions();
    assertEq(actions.length, 0);

    actions = shareHandler.getAllUnprocessedActions();
    assertEq(actions.length, 1);

    tsa.processDeposit(actions[0].actionId);
    actions = shareHandler.getAllPendingActions();

    assertEq(actions[0].amount, 1e18);
    // Ids start from 0, so this is the second deposit
    assertEq(actions[0].actionId, 1);
    assertEq(address(actions[0].vault), address(tsa));
    assertEq(actions[0].fallbackDest, address(alice));
    assertEq(actions[0].withdrawalConnector, address(connectorOut));
    assertEq(actions[0].withdrawalRecipient, address(this));

    // only received 0.5 shares
    assertEq(tsa.balanceOf(address(shareHandler)), 0.5e18);

    vm.deal(address(shareHandler), 1 ether);
    shareHandler.completeAction(IBaseTSA(address(tsa)), actions[0].actionId);
    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 0);

    // Shares are sent to the bridge as they were bridged out
    assertEq(tsa.balanceOf(address(bridgeOut)), 0.5e18);

    actions = shareHandler.getAllUserActions(alice);
    assertEq(actions.length, 1);
    assertEq(actions[0].amount, 1e18);
    assertEq(address(actions[0].vault), address(tsa));
    assertEq(actions[0].fallbackDest, address(alice));
    assertEq(actions[0].withdrawalConnector, address(connectorOut));
    assertEq(actions[0].withdrawalRecipient, address(this));
    // only received 0.5 shares
    assertEq(actions[0].amountReceived, 0.5e18);
    assertEq(actions[0].messageId, keccak256(abi.encode(2)));

    // withdrawal
    tsa.transfer(address(alice), 0.5e18);
    vm.startPrank(alice);
    tsa.approve(address(shareHandler), 1000e18);
    shareHandler.initiateWithdrawal(IBaseTSA(address(tsa)), address(alice), address(connectorIn), address(this), 0.5e18);
    vm.stopPrank();

    // unprocessed, but not ready for the next step (i.e. not pending)
    actions = shareHandler.getAllUnprocessedActions();
    assertEq(actions.length, 1);

    actions = shareHandler.getAllPendingActions();
    assertEq(actions.length, 0);

    tsa.processWithdrawalRequests(1);

    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 1);
    assertEq(actions[0].amount, 0.5e18);
    // ids start from 0
    assertEq(actions[0].actionId, (0 | (1 << 255)));
    assertEq(address(actions[0].vault), address(tsa));
    assertEq(actions[0].fallbackDest, address(alice));
    assertEq(actions[0].withdrawalConnector, address(connectorIn));
    assertEq(actions[0].withdrawalRecipient, address(this));

    assertEq(markets["weth"].erc20.balanceOf(address(shareHandler)), 1e18);

    shareHandler.completeAction(IBaseTSA(address(tsa)), actions[0].actionId);

    actions = shareHandler.getAllPendingActions();

    assertEq(actions.length, 0);
    assertEq(tsa.balanceOf(address(alice)), 0);
    assertEq(markets["weth"].erc20.balanceOf(address(bridgeIn)), 1e18);

    actions = shareHandler.getAllUserActions(alice);

    assertEq(actions.length, 2);

    assertEq(actions[0].messageId, keccak256(abi.encode(2)));
    assertEq(actions[1].messageId, keccak256(abi.encode(1)));
  }
}
