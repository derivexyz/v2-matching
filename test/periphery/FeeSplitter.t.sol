pragma solidity ^0.8.18;

import "../../src/periphery/FeeSplitter.sol";
import "v2-core/test/integration-tests/shared/IntegrationTestBase.t.sol";


contract FeeSplitterTest is IntegrationTestBase {
  FeeSplitter public feeSplitter;

  function setUp() public {
    _setupIntegrationTestComplete();

    feeSplitter = new FeeSplitter(subAccounts, srm);
  }

  function test_split() public {
    feeSplitter.split();
  }
}
