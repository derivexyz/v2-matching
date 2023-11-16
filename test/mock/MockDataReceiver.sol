// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {IDataReceiver} from "v2-core/src/interfaces/IDataReceiver.sol";
import {MockFeeds} from "v2-core/test/shared/mocks/MockFeeds.sol";

contract MockDataReceiver is IDataReceiver {
  // update mocked feed
  function acceptData(bytes memory data) external {
    (address mockedFeed, uint price) = abi.decode(data, (address, uint));
    MockFeeds(mockedFeed).setSpot(price, 1e18);
  }
}
