// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import "./IMatching.sol";

interface IAtomicSigner {
  function signActionViaPermit(IMatching.Action memory action, bytes memory extraData, bytes memory signerSig) external;
}
