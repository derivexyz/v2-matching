// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "./Matching.sol";
import "./interfaces/IActionVerifier.sol";
import "./interfaces/IAtomicSigner.sol";

// Wrapper contract for the "Executor" role within the Matching contract. Allows for calling out to the singer of an
// action if their signature is "0" before forwarding the request onto Matching itself.

contract AtomicSigningExecutor {
  struct AtomicAction {
    bool isAtomic;
    bytes extraData;
  }

  Matching public immutable matching;

  constructor(Matching _matching) {
    matching = _matching;
  }

  function atomicVerifyAndMatch(
    IActionVerifier.Action[] memory actions,
    bytes[] memory signatures,
    bytes memory actionData,
    AtomicAction[] memory atomicActionData
  ) external onlyTradeExecutor {
    for (uint i = 0; i < actions.length; i++) {
      AtomicAction memory atomicAction = atomicActionData[i];
      if (atomicAction.isAtomic) {
        // Call the signer of the action
        IAtomicSigner signer = IAtomicSigner(actions[i].signer);
        signer.signActionViaPermit(actions[i], atomicAction.extraData, signatures[i]);
      }
    }
    matching.verifyAndMatch(actions, signatures, actionData);
  }

  modifier onlyTradeExecutor() {
    require(matching.tradeExecutors(msg.sender), "AtomicSigningExecutor: Only trade executors can call this function");
    _;
  }
}
