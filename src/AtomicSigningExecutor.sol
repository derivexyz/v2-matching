
import "./Matching.sol";// SPDX-License-Identifier: MIT
import "./interfaces/IActionVerifier.sol";

interface IAtomicSigner {
  struct AtomicAction {
    bool isAtomic;
    bytes extraData;
  }

  function signActionViaPermit(IMatching.Action memory action, bytes memory extraData, bytes memory signerSig) external;
}


// Wrapper contract for the "Executor" role within the Matching contract. Allows for calling out to the singer of an
// action if their signature is "0" before forwarding the request onto Matching itself.

contract AtomicSigningExecutor {
  Matching public immutable matching;

  constructor(Matching _matching) {
    matching = _matching;
  }

  function atomicVerifyAndMatch(
    IActionVerifier.Action[] memory actions,
    bytes[] memory signatures,
    bytes memory actionData,
    IAtomicSigner.AtomicAction[] memory atomicActionData
  )
    public
    onlyTradeExecutor
  {
    for (uint i = 0; i < actions.length; i++) {
      IAtomicSigner.AtomicAction memory atomicAction = atomicActionData[i];
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