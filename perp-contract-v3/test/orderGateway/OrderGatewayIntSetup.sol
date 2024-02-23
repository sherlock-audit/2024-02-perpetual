// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../clearingHouse/ClearingHouseIntSetup.sol";
import { OrderGateway } from "../../src/orderGateway/OrderGateway.sol";
import { TestMaker } from "../helper/TestMaker.sol";

contract OrderGatewayIntSetup is ClearingHouseIntSetup {
    OrderGateway public orderGateway;
    TestMaker maker;

    function setUp() public virtual override {
        ClearingHouseIntSetup.setUp();

        orderGateway = new OrderGateway();
        _enableInitialize(address(orderGateway));
        orderGateway.initialize(address(addressManager));

        addressManager.setAddress(ORDER_GATEWAY, address(orderGateway));

        maker = _newMarketWithTestMaker(marketId);
        config.setOrderDelaySeconds(60);
    }

    function test_excludeFromCoverageReport() public virtual override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
