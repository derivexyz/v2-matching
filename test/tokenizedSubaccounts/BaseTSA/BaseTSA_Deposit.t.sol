pragma solidity ^0.8.18;

import "../utils/CCTSATestUtils.sol";
/*
Deposits:
- ✅multiple deposits can be processed (dont have to be sequential)
- ✅depositors get different amounts of shares based on changes to NAV
- ✅deposits are blocked when there is a liquidation
- ✅deposits cannot be processed if they are already processed
- ✅deposits below the minimum are rejected
- ✅deposits cannot be queued if cap is exceeded
- ✅deposits CAN be processed if cap is exceeded
- ✅deposits will be scaled by the depositScale
- any deposit will collect fees correctly (before totalSupply is changed)
*/

contract CCTSA_BaseTSA_DepositTests is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA("weth");
    setupCCTSA();
  }

  function testMessyDeposits() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(tsa), 10e18);
    uint depositId = cctsa.initiateDeposit(1e18, address(this));
    cctsa.processDeposit(depositId);
    assertEq(cctsa.balanceOf(address(this)), 1e18);
    _executeDeposit(0.8e18);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0.2e18);
    assertEq(subAccounts.getBalance(cctsa.subAccount(), markets["weth"].base, 0), 0.8e18);
    depositId = cctsa.initiateDeposit(1e18, address(this));
    cctsa.processDeposit(depositId);
    assertEq(cctsa.balanceOf(address(this)), 2e18);
    cctsa.requestWithdrawal(0.25e18);
    assertEq(cctsa.balanceOf(address(this)), 1.75e18);
    assertEq(cctsa.totalPendingWithdrawals(), 0.25e18);
    vm.warp(block.timestamp + 10 minutes + 1);
    cctsa.processWithdrawalRequests(1);
    assertEq(cctsa.balanceOf(address(this)), 1.75e18);
  }

  function testDepositsAreProcessedSequentially() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    uint numDeposits = 5;
    markets["weth"].erc20.mint(address(this), depositAmount * numDeposits);
    markets["weth"].erc20.approve(address(tsa), depositAmount * numDeposits);

    uint[] memory depositIds = new uint[](numDeposits);
    // Initiate and process multiple deposits
    for (uint i = 0; i < numDeposits; i++) {
      depositIds[i] = cctsa.initiateDeposit(depositAmount, address(this));
    }

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), 0);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount * numDeposits);

    for (uint i = 0; i < numDeposits; i++) {
      BaseTSA.DepositRequest memory depReq = cctsa.queuedDeposit(depositIds[i]);
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, 0);
    }

    // Process all
    cctsa.processDeposits(depositIds);

    for (uint i = 0; i < numDeposits; i++) {
      BaseTSA.DepositRequest memory depReq = cctsa.queuedDeposit(depositIds[i]);
      // There are no partial deposits, so amountDepositAsset doesn't need to change
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, depositAmount);
    }

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), depositAmount * numDeposits);
  }

  function testDepositsGetDifferentAmountsOfSharesBasedOnChangesToNAV() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    uint numDeposits = 5;
    markets["weth"].erc20.mint(address(this), depositAmount * numDeposits);
    markets["weth"].erc20.approve(address(tsa), depositAmount * numDeposits);

    uint[] memory depositIds = new uint[](numDeposits);
    // Initiate and process multiple deposits
    for (uint i = 0; i < numDeposits; i++) {
      depositIds[i] = cctsa.initiateDeposit(depositAmount, address(this));
    }

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), 0);
    assertEq(cctsa.totalPendingDeposits(), depositAmount * numDeposits);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount * numDeposits);
    assertEq(cctsa.getNumShares(1e18), 1e18);
    assertEq(cctsa.getSharesValue(1e18), 1e18);

    for (uint i = 0; i < numDeposits; i++) {
      BaseTSA.DepositRequest memory depReq = cctsa.queuedDeposit(depositIds[i]);
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, 0);
    }

    // Process 2
    cctsa.processDeposit(depositIds[1]);
    cctsa.processDeposit(depositIds[0]);

    for (uint i = 0; i < 2; i++) {
      BaseTSA.DepositRequest memory depReq = cctsa.queuedDeposit(depositIds[i]);
      // There are no partial deposits, so amountDepositAsset doesn't need to change
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, depositAmount);
    }

    // Get 2 shares
    assertEq(cctsa.balanceOf(address(this)), depositAmount * 2, "Share balance of depositor");
    assertEq(cctsa.totalSupply(), depositAmount * 2, "TSA total supply");
    assertEq(cctsa.totalPendingDeposits(), depositAmount * 3, "Total pending deposits");
    assertEq(cctsa.getNumShares(1e18), 1e18);
    assertEq(cctsa.getSharesValue(1e18), 1e18);

    // Double the value of the pool
    markets["weth"].erc20.mint(address(tsa), depositAmount * 2);

    assertEq(cctsa.getNumShares(1e18), 0.5e18);
    assertEq(cctsa.getSharesValue(1e18), 2e18);

    cctsa.processDeposit(depositIds[3]);
    cctsa.processDeposit(depositIds[2]);

    for (uint i = 0; i < 2; i++) {
      BaseTSA.DepositRequest memory depReq = cctsa.queuedDeposit(depositIds[i + 2]);
      // There are no partial deposits, so amountDepositAsset doesn't need to change
      assertEq(depReq.amountDepositAsset, depositAmount, "Deposit amount");
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, depositAmount / 2, "Shares received");
    }

    // Get 1 more share, as each share is now 2 weth worth
    assertEq(cctsa.balanceOf(address(this)), depositAmount * 3, "Share balance");

    // Double the value of the pool (has 6)
    markets["weth"].erc20.mint(address(tsa), depositAmount * 6);

    cctsa.processDeposit(depositIds[4]);

    {
      BaseTSA.DepositRequest memory depReq = cctsa.queuedDeposit(depositIds[4]);
      assertEq(depReq.sharesReceived, depositAmount / 4, "Shares received");
    }

    // Get 0.25 more shares, as each share is now 4 weth worth (3.25 total)
    assertEq(cctsa.balanceOf(address(this)), depositAmount * 3.25e2 / 1e2, "Share balance");
  }

  function testDepositsAreBlockedWhenThereIsALiquidation() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    // Initiate a deposit
    uint depositId = cctsa.initiateDeposit(depositAmount, address(this));

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), 0);
    assertEq(cctsa.totalPendingDeposits(), depositAmount);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);

    // Create an insolvent auction
    uint liquidationId = _createInsolventAuction();

    // Try to process the deposit
    assertEq(cctsa.isBlocked(), true);
    vm.expectRevert(BaseTSA.BTSA_Blocked.selector);
    cctsa.processDeposit(depositId);

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), 0);
    assertEq(cctsa.totalPendingDeposits(), depositAmount);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);
  }

  function testDepositsCannotBeProcessedIfTheyAreAlreadyProcessed() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    // Initiate a deposit
    uint depositId = cctsa.initiateDeposit(depositAmount, address(this));

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), 0);
    assertEq(cctsa.totalPendingDeposits(), depositAmount);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);

    // Process the deposit
    cctsa.processDeposit(depositId);

    // Check state is as expected
    assertEq(cctsa.balanceOf(address(this)), depositAmount);
    assertEq(cctsa.totalPendingDeposits(), 0);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);

    // Try to process the deposit again
    vm.expectRevert(BaseTSA.BTSA_DepositAlreadyProcessed.selector);
    cctsa.processDeposit(depositId);
  }

  function testDepositsQueueFailureReasons() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    BaseTSA.TSAParams memory params = cctsa.getTSAParams();

    params.minDepositValue = 1.01e18;
    cctsa.setTSAParams(params);

    vm.expectRevert(BaseTSA.BTSA_DepositBelowMinimum.selector);
    cctsa.initiateDeposit(1e18, address(this));

    params.minDepositValue = 0;
    params.depositCap = 0.99e18;
    cctsa.setTSAParams(params);

    vm.expectRevert(BaseTSA.BTSA_DepositCapExceeded.selector);
    cctsa.initiateDeposit(1e18, address(this));

    params.depositCap = 1e18;
    cctsa.setTSAParams(params);
    uint depositId = cctsa.initiateDeposit(1e18, address(this));

    // Can process even if cap is lower

    params.depositCap = 0;
    cctsa.setTSAParams(params);
    cctsa.processDeposit(depositId);
  }
}
