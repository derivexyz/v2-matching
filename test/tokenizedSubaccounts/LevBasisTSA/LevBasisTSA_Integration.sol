pragma solidity ^0.8.18;

import "../../../src/AtomicSigningExecutor.sol";
import "../utils/LBTSATestUtils.sol";

contract LevBasisTSA_IntegrationTests is LBTSATestUtils {
  using SignedMath for int;

  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLBTSA();
    setupLBTSA();
  }

  function testTradingValidation() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    IActionVerifier.Action memory action = _getSpotTradeAction(10e18, 2000e18);

    vm.prank(signer);
    vm.expectRevert(LeveragedBasisTSA.LBT_PostTradeDeltaOutOfRange.selector);
    lbtsa.signActionData(action, "");

    // Open basis position 3 times
    for (uint i = 0; i < 1; i++) {
      // Buy spot
      _tradeSpot(0.2e18, 2000e18);

      // Short perp
      _tradePerp(-0.2e18, 2000e18);
    }

    // Close out positions in reverse
    for (uint i = 0; i < 1; i++) {
      // Buy back perp
      _tradePerp(0.2e18, 2000e18);

      // Sell spot
      _tradeSpot(-0.2e18, 2000e18);
    }
  }

  function testAtomicSigning() public {
    _depositToTSA(10e18);
    _executeDeposit(10e18);

    AtomicSigningExecutor executor = new AtomicSigningExecutor(matching);

    matching.setTradeExecutor(address(executor), true);

    uint price = 2000e18;
    int amount = 0.2e18;

    bytes memory tradeData = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].base),
        subId: 0,
        limitPrice: int(price),
        desiredAmount: int(amount.abs()),
        worstFee: 1e18,
        recipientId: tsaSubacc,
        isBid: amount > 0
      })
    );

    bytes memory tradeMaker = abi.encode(
      ITradeModule.TradeData({
        asset: address(markets["weth"].base),
        subId: 0,
        limitPrice: int(price),
        desiredAmount: int(amount.abs()),
        worstFee: 1e18,
        recipientId: nonVaultSubacc,
        isBid: amount < 0
      })
    );

    IActionVerifier.Action[] memory actions = new IActionVerifier.Action[](2);
    bytes[] memory signatures = new bytes[](2);

    actions[0] = IActionVerifier.Action({
      subaccountId: tsaSubacc,
      nonce: ++tsaNonce,
      module: tradeModule,
      data: tradeData,
      expiry: block.timestamp + 8 minutes,
      owner: address(tsa),
      signer: address(tsa)
    });

    (actions[1], signatures[1]) = _createActionAndSign(
      nonVaultSubacc,
      ++nonVaultNonce,
      address(tradeModule),
      tradeMaker,
      block.timestamp + 1 days,
      nonVaultAddr,
      nonVaultAddr,
      nonVaultPk
    );

    signatures[0] = _signAction(matching.getActionHash(actions[0]), signerPk);

    AtomicSigningExecutor.AtomicAction[] memory atomicActions = new AtomicSigningExecutor.AtomicAction[](2);
    atomicActions[0] = AtomicSigningExecutor.AtomicAction({isAtomic: true, extraData: ""});
    atomicActions[1] = AtomicSigningExecutor.AtomicAction({isAtomic: false, extraData: ""});

    vm.startPrank(tradeExecutor);
    executor.atomicVerifyAndMatch(
      actions,
      signatures,
      _createMatchedTrade(
        tsaSubacc,
        nonVaultSubacc,
        uint(amount),
        int(price),
        // trade fees
        0,
        0
      ),
      atomicActions
    );
    vm.stopPrank();
  }
}
