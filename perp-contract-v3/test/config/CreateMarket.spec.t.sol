// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import { Config } from "../../src/config/Config.sol";
import { LibError } from "../../src/common/LibError.sol";
import "../MockSetup.sol";

contract CreateMarketTest is MockSetup {
    Config config = new Config();

    function setUp() public virtual override {
        MockSetup.setUp();

        _enableInitialize(address(config));
        config.initialize(mockAddressManager);
        config.createMarket(marketId, priceFeedId);
    }

    function test_RevertIf_MarketExists() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.MarketExists.selector, marketId));
        config.createMarket(marketId, priceFeedId);
    }
}
