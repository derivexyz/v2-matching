// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

interface IBridge {
  function bridge(
    address receiver_,
    uint amount_,
    uint msgGasLimit_,
    address connector_,
    bytes calldata execPayload_,
    bytes calldata options_
  ) external payable;
}

interface IConnector {
  function getMinFees(uint msgGasLimit_, uint payloadSize_) external view returns (uint totalFees);

  function getMessageId() external view returns (bytes32);
}

interface IBridgeExt is IBridge {
  function token() external view returns (address);
}

interface IConnectorPlugExt is IConnector {
  function bridge__() external returns (IBridge);
}

interface IBaseTSA {
  struct BaseTSAAddresses {
    address subAccounts;
    address auction;
    address wrappedDepositAsset;
    address cash;
    IERC20Metadata depositAsset;
    address manager;
    address matching;
  }

  /// @dev A withdrawal is considered complete when amountShares is 0. They can be partially completed.
  struct WithdrawalRequest {
    address beneficiary;
    uint amountShares;
    uint timestamp;
    uint assetsReceived;
  }

  /// @dev A deposit is considered complete when sharesReceived is > 0. There are no partially complete deposits.
  struct DepositRequest {
    address recipient;
    uint amountDepositAsset;
    uint timestamp;
    uint sharesReceived;
  }

  function getBaseTSAAddresses() external view returns (BaseTSAAddresses memory);

  function initiateDeposit(uint amount, address recipient) external returns (uint actionId);

  function requestWithdrawal(uint amount) external returns (uint actionId);

  function queuedDeposit(uint actionId) external view returns (DepositRequest memory);

  function queuedWithdrawal(uint actionId) external view returns (WithdrawalRequest memory);
}

contract TSAShareHandler is Ownable2Step {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct PendingTSAAction {
    /// @dev either a deposit or withdrawal id for the given TSA. actionId = isDeposit ? actionId : actionId | 1 << 255
    uint actionId;
    IBaseTSA vault;
    uint amount;
    address fallbackDest;
    address withdrawalConnector;
    address withdrawalRecipient;
    /// @dev If amountReceived > 0, that means action has been processed
    uint amountReceived;
    /// @dev If amountReceived > 0 and messageId == 0, that means funds were sent to the fallback
    bytes32 messageId;
  }

  uint public withdrawalMinGasLimit = 500_000;

  mapping(address keeper => bool isKeeper) internal keepers;

  /// @dev vaultActionId = keccak256(abi.encodePacked(vaultAddr, isDeposit ? actionId : actionId | 1 << 255));
  mapping(bytes32 vaultActionId => PendingTSAAction) internal actions;
  mapping(address fallbackDest => EnumerableSet.Bytes32Set vaultActionId) internal pendingActionIds;
  mapping(address fallbackDest => EnumerableSet.Bytes32Set vaultActionId) internal allActionIds;
  EnumerableSet.AddressSet internal pendingUsers;

  constructor() {}

  receive() external payable {}

  ///////////
  // Admin //
  ///////////
  function setWithdrawalMinGasLimit(uint limit) external onlyOwner {
    withdrawalMinGasLimit = limit;
  }

  function recoverEth(address payable recipient) external onlyOwner {
    recipient.transfer(address(this).balance);
  }

  function recoverERC20(IERC20Metadata token, address recipient) external onlyOwner {
    token.transfer(recipient, token.balanceOf(address(this)));
  }

  function setKeeper(address newKeeper, bool isKeeper) external onlyOwner {
    keepers[newKeeper] = isKeeper;
  }

  //////////////
  // Deposits //
  //////////////

  /// @notice if withdrawalConnector is address(0) or invalid, funds will be sent to fallbackDest
  function initiateDeposit(
    IBaseTSA toVault,
    address fallbackDest,
    address withdrawalConnector,
    address withdrawalRecipient,
    uint amount
  ) external {
    require(fallbackDest != address(0), "fallbackDest cannot be 0");

    IBaseTSA.BaseTSAAddresses memory tsaAddrs = toVault.getBaseTSAAddresses();

    tsaAddrs.depositAsset.transferFrom(msg.sender, address(this), amount);
    tsaAddrs.depositAsset.approve(address(toVault), amount);

    _addPendingAction(
      toVault,
      toVault.initiateDeposit(amount, address(this)),
      amount,
      fallbackDest,
      withdrawalConnector,
      withdrawalRecipient,
      true
    );
  }

  /////////////////
  // Withdrawals //
  /////////////////

  function initiateWithdrawal(
    IBaseTSA fromVault,
    address fallbackDest,
    address withdrawalConnector,
    address withdrawalRecipient,
    uint amount
  ) external {
    require(fallbackDest != address(0), "fallbackDest cannot be 0");

    IBaseTSA.BaseTSAAddresses memory tsaAddrs = fromVault.getBaseTSAAddresses();

    IERC20Metadata(address(fromVault)).transferFrom(msg.sender, address(this), amount);

    _addPendingAction(
      fromVault,
      fromVault.requestWithdrawal(amount),
      amount,
      fallbackDest,
      withdrawalConnector,
      withdrawalRecipient,
      false
    );
  }

  ////////////
  // Keeper //
  ////////////

  /// @param actionId isDeposit ? actionId : actionId | 1 << 255
  function completeAction(IBaseTSA toVault, uint actionId) external onlyKeeper {
    _completeAction(toVault, actionId);
  }

  /// @param actionId isDeposit ? actionId : actionId | 1 << 255
  function completeActions(IBaseTSA[] memory toVault, uint[] memory actionId) external onlyKeeper {
    for (uint i = 0; i < toVault.length; i++) {
      _completeAction(toVault[i], actionId[i]);
    }
  }

  ////////////
  // Shared //
  ////////////

  function _addPendingAction(
    IBaseTSA vault,
    uint actionId,
    uint amount,
    address fallbackDest,
    address withdrawalConnector,
    address withdrawalRecipient,
    bool isDeposit
  ) internal {
    if (!isDeposit) {
      actionId = actionId | 1 << 255;
    }

    bytes32 vaultActionId = keccak256(abi.encodePacked(vault, actionId));

    actions[vaultActionId] = PendingTSAAction({
      actionId: actionId,
      vault: vault,
      amount: amount,
      fallbackDest: fallbackDest,
      withdrawalConnector: withdrawalConnector,
      withdrawalRecipient: withdrawalRecipient,
      messageId: bytes32(0),
      amountReceived: 0
    });
    pendingActionIds[fallbackDest].add(vaultActionId);
    allActionIds[fallbackDest].add(vaultActionId);
    pendingUsers.add(fallbackDest);

    emit ActionInitiated(vault, fallbackDest, actionId, withdrawalRecipient, withdrawalConnector, amount);
  }

  function _completeAction(IBaseTSA toVault, uint actionId) internal {
    bytes32 vaultActionId = keccak256(abi.encodePacked(toVault, actionId));

    PendingTSAAction storage pendingAction = actions[vaultActionId];

    require(
      pendingActionIds[pendingAction.fallbackDest].contains(vaultActionId), "action not found or already processed"
    );

    bool isDeposit = actionId & (1 << 255) == 0;

    IBaseTSA.BaseTSAAddresses memory tsaAddrs = toVault.getBaseTSAAddresses();
    IERC20Metadata withdrawalToken;
    uint amount;

    if (isDeposit) {
      IBaseTSA.DepositRequest memory depReq = toVault.queuedDeposit(actionId);
      withdrawalToken = IERC20Metadata(address(toVault));
      require(depReq.sharesReceived > 0, "deposit to TSA not complete");
      amount = depReq.sharesReceived;
    } else {
      actionId = actionId & ~uint(1 << 255);
      IBaseTSA.WithdrawalRequest memory withReq = toVault.queuedWithdrawal(actionId);
      withdrawalToken = IERC20Metadata(address(tsaAddrs.depositAsset));
      require(withReq.amountShares == 0, "withdrawal from TSA not complete");
      amount = withReq.assetsReceived;
    }

    bytes32 messageId = _processBridge(
      withdrawalToken,
      amount,
      pendingAction.withdrawalRecipient,
      pendingAction.withdrawalConnector,
      pendingAction.fallbackDest
    );

    pendingAction.amountReceived = amount;
    pendingAction.messageId = messageId;

    // Now pop the pending deposit from the array
    pendingActionIds[pendingAction.fallbackDest].remove(vaultActionId);
    if (pendingActionIds[pendingAction.fallbackDest].length() == 0) {
      pendingUsers.remove(pendingAction.fallbackDest);
    }
  }

  ////////////
  // Bridge //
  ////////////
  function _processBridge(
    IERC20Metadata token,
    uint amount,
    address recipient,
    address bridgeConnector,
    address fallbackAddr
  ) internal returns (bytes32 messageId) {
    (address bridge, address bridgeToken) = _tryGetBridgeDetails(bridgeConnector);

    bool sendToFallback = true;

    if (bridgeToken == address(token) && recipient != address(0)) {
      messageId = IConnectorPlugExt(bridgeConnector).getMessageId();
      bool success = _tryBridge(token, IBridgeExt(bridge), recipient, amount, bridgeConnector);
      if (success) {
        sendToFallback = false;
      }
    }

    if (sendToFallback) {
      token.transfer(fallbackAddr, amount);
    }
  }

  ///////////////////
  // Try/Catch Txs //
  ///////////////////

  /// @dev Returns zero address if bridge is not found, connector is invalid or no token() function on bridge address
  function _tryGetBridgeDetails(address connector) internal returns (address bridge, address bridgeToken) {
    (bool success, bytes memory data) = connector.call(abi.encodeWithSignature("bridge__()"));
    if (!success || data.length == 0) {
      return (address(0), address(0));
    }
    bridge = abi.decode(data, (address));

    (success, data) = bridge.call(abi.encodeWithSignature("token()"));
    if (!success || data.length == 0) {
      return (address(0), address(0));
    }
    bridgeToken = abi.decode(data, (address));
    return (bridge, bridgeToken);
  }

  function _tryBridge(
    IERC20Metadata withdrawToken,
    IBridgeExt bridge,
    address recipient,
    uint amount,
    address withdrawConnector
  ) internal returns (bool) {
    withdrawToken.approve(address(bridge), amount);

    uint fees = IConnectorPlugExt(withdrawConnector).getMinFees(withdrawalMinGasLimit, 0);

    if (fees > address(this).balance) {
      // We revert if not enough ETH present at this contract address; so we can try again later
      revert("INSUFFICIENT_ETH_BALANCE");
    }
    try bridge.bridge{value: fees}(
      recipient, amount, withdrawalMinGasLimit, withdrawConnector, new bytes(0), new bytes(0)
    ) {
      return true;
    } catch {
      return false;
    }
  }

  ///////////
  // Views //
  ///////////

  function getUserPendingActions(address user) external view returns (PendingTSAAction[] memory pendingActions) {
    pendingActions = new PendingTSAAction[](pendingActionIds[user].length());
    bytes32[] memory vaultActionIds = pendingActionIds[user].values();
    for (uint i = 0; i < vaultActionIds.length; i++) {
      pendingActions[i] = actions[vaultActionIds[i]];
    }
  }

  function getAllUserActions(address user) external view returns (PendingTSAAction[] memory allActions) {
    allActions = new PendingTSAAction[](allActionIds[user].length());
    bytes32[] memory vaultActionIds = allActionIds[user].values();
    for (uint i = 0; i < vaultActionIds.length; i++) {
      allActions[i] = actions[vaultActionIds[i]];
    }
  }

  function getAllPendingActions() external view returns (PendingTSAAction[] memory pendingActions) {
    address[] memory users = pendingUsers.values();
    uint actionCount = 0;
    for (uint i = 0; i < users.length; i++) {
      actionCount += pendingActionIds[users[i]].length();
    }

    pendingActions = new PendingTSAAction[](actionCount);

    uint index = 0;

    for (uint i = 0; i < users.length; i++) {
      bytes32[] memory vaultActionIds = pendingActionIds[users[i]].values();
      for (uint j = 0; j < vaultActionIds.length; j++) {
        PendingTSAAction storage action = actions[vaultActionIds[j]];
        if (action.actionId & (1 << 255) == 0) {
          // is a deposit
          if (action.vault.queuedDeposit(action.actionId).sharesReceived > 0) {
            pendingActions[index++] = actions[vaultActionIds[j]];
          }
        } else {
          if (action.vault.queuedWithdrawal(action.actionId & ~uint(1 << 255)).amountShares == 0) {
            pendingActions[index++] = actions[vaultActionIds[j]];
          }
        }
      }
    }

    assembly {
      mstore(pendingActions, index)
    }

    return pendingActions;
  }

  function getAllUnprocessedActions() external view returns (PendingTSAAction[] memory pendingActions) {
    address[] memory users = pendingUsers.values();
    uint actionCount = 0;
    for (uint i = 0; i < users.length; i++) {
      actionCount += pendingActionIds[users[i]].length();
    }

    pendingActions = new PendingTSAAction[](actionCount);

    for (uint i = 0; i < users.length; i++) {
      bytes32[] memory vaultActionIds = pendingActionIds[users[i]].values();
      for (uint j = 0; j < vaultActionIds.length; j++) {
        pendingActions[--actionCount] = actions[vaultActionIds[j]];
      }
    }
  }

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyKeeper() {
    require(keepers[msg.sender], "only keeper");
    _;
  }

  ////////////
  // Events //
  ////////////

  event ActionInitiated(
    IBaseTSA indexed vault,
    address indexed fallbackDest,
    uint actionId,
    address withdrawalRecipient,
    address withdrawalConnector,
    uint amount
  );
}
