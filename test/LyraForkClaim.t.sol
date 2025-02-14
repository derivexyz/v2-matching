pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "v2-core/scripts/types.sol";
import "forge-std/console2.sol";

import "v2-core/src/risk-managers/StandardManager.sol";
import "v2-core/src/risk-managers/SRMPortfolioViewer.sol";
import "v2-core/src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "./ForkBase.t.sol";
import {ITradeModule} from "../src/interfaces/ITradeModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import "../scripts/config/config.sol";
import {PositionTracking} from "v2-core/src/assets/utils/PositionTracking.sol";
import {WLWrappedERC20Asset} from "v2-core/src/assets/WLWrappedERC20Asset.sol";

contract LyraForkClaim is ForkBase {
  function setUp() external {}

  function testFork() external checkFork {
    vm.deal(address(0xBa0512b8F70Cd73939F6b22e965950B977b372c5), 1 ether);
    vm.startPrank(0xBa0512b8F70Cd73939F6b22e965950B977b372c5);

    _call(address(0x2f8C5a3BBd69443B6e462F563bA0EaB4317F995b), hex"d1058e59");

    _call(
      address(0x7499d654422023a407d92e1D83D387d81BC68De1),
      hex"7cbc23730000000000000000000000000000000000000000000000964ac76731fcf800000000000000000000000000000000000000000000000000000000000000000000"
    );
  }

  function _call(address target, bytes memory data) internal returns (bytes memory) {
    console.log(target);
    console.log(",");
    console.logBytes(data);
    (bool success, bytes memory result) = target.call(data);
    require(success, "call failed");
    return result;
  }
}
