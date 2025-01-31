pragma solidity 0.8.20;

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
import {LyraERC20} from "v2-core/src/l2/LyraERC20.sol";

contract LyraForkDepositBaseTest is ForkBase {
  function testFork() external checkFork {
    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);

    StandardManager srm = StandardManager(_getV2CoreContract("core", "srm"));

    LyraERC20 susde = LyraERC20(_getV2CoreContract("shared", "susde"));
    susde.configureMinter(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), true);

    susde.mint(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 100 ether);

    WrappedERC20Asset wSusde = WrappedERC20Asset(_getV2CoreContract("sUSDe", "base"));

    susde.approve(address(wSusde), 100 ether);

    wSusde.deposit(1527, 100 ether);
  }
}
