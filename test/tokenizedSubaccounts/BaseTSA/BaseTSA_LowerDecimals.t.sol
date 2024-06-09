pragma solidity ^0.8.18;

import "../TSATestUtils.sol";

/**
 * For both lower and higher decimal assets:
 * - ✅deposits are handled
 * - ✅withdrawals are handled
 * - ✅fees are collected
 * - can deposit, trade and withdraw with subaccount
 * - ✅upgrades are handled correctly
 */
contract BaseTSA_LowerDecimalsTests is TSATestUtils {
  MockERC20 erc20;
  WrappedERC20Asset base;

  function setUp() public override {
    super.setUp();

    erc20 = new MockERC20("lowerDec", "lowerDec");
    erc20.setDecimals(6);

    base = new WrappedERC20Asset(subAccounts, erc20);

    deployPredeposit(address(erc20));
  }

  function testDeposits() public {
    upgradeToMockTSA(address(base));

    assertEq(erc20.balanceOf(address(this)), 0);
    assertEq(mockTsa.balanceOf(address(this)), 0);

    erc20.mint(address(this), 1000e6);
    erc20.approve(address(mockTsa), 1000e6);

    mockTsa.processDeposit(mockTsa.initiateDeposit(1000e6, address(this)));

    // since value started at 0, shares are 1:1

    assertEq(erc20.balanceOf(address(this)), 0);
    // Shares are in the same decimals as the base asset
    assertEq(mockTsa.balanceOf(address(this)), 1000e6);

    // Account value is set to same decimals as the base asset
    mockTsa.setAccountValue(3000e6);

    // since value is 3000, shares are 3:1

    erc20.mint(address(this), 300e6);
    erc20.approve(address(mockTsa), 300e6);

    mockTsa.processDeposit(mockTsa.initiateDeposit(300e6, address(this)));

    assertEq(erc20.balanceOf(address(this)), 0);
    assertEq(mockTsa.balanceOf(address(this)), 1100e6);
  }

  function testWithdrawals() public {
    upgradeToMockTSA(address(base));

    erc20.mint(address(this), 1000e6);
    erc20.approve(address(mockTsa), 1000e6);

    mockTsa.processDeposit(mockTsa.initiateDeposit(1000e6, address(this)));

    mockTsa.setAccountValue(3000e6);

    mockTsa.requestWithdrawal(100e6);

    assertEq(erc20.balanceOf(address(this)), 0);
    assertEq(mockTsa.balanceOf(address(this)), 900e6);
    assertEq(mockTsa.totalPendingWithdrawals(), 100e6);

    vm.warp(block.timestamp + 10 minutes + 1);
    mockTsa.processWithdrawalRequests(1);

    // get 300 out because "account value" is 3000.
    assertEq(erc20.balanceOf(address(this)), 300e6);
    assertEq(mockTsa.balanceOf(address(this)), 900e6);
  }

  function testFeeCollected() public {
    upgradeToMockTSA(address(base));

    erc20.mint(address(this), 1000e6);
    erc20.approve(address(mockTsa), 1000e6);

    mockTsa.processDeposit(mockTsa.initiateDeposit(1000e6, address(this)));

    // Account value is irrelevant to fee collection
    mockTsa.setAccountValue(0);

    BaseTSA.TSAParams memory params = mockTsa.getTSAParams();
    params.feeRecipient = address(alice);
    params.managementFee = 1e16; // 1%
    mockTsa.setTSAParams(params);

    vm.warp(block.timestamp + 365 days);

    mockTsa.collectFee();

    assertEq(mockTsa.balanceOf(address(alice)), 10e6);
    assertEq(mockTsa.totalSupply(), 1010e6);
  }

  function testBalancesAreMaintainedWhenUpgraded_lower() public {
    TokenizedSubAccount preTsa = TokenizedSubAccount(address(proxy));

    erc20.mint(address(this), 1000e6);
    erc20.approve(address(preTsa), 1000e6);

    preTsa.depositFor(address(this), 1000e6);

    assertEq(preTsa.balanceOf(address(this)), 1000e6);

    upgradeToMockTSA(address(base));

    assertEq(mockTsa.balanceOf(address(this)), 1000e6);
    mockTsa.setAccountValue(1000e6);

    mockTsa.requestWithdrawal(1000e6);
    mockTsa.processWithdrawalRequests(1);

    assertEq(erc20.balanceOf(address(this)), 1000e6);
    assertEq(mockTsa.balanceOf(address(this)), 0);
  }
}
