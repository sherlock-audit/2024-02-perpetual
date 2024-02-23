// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "../../src/common/LibConstant.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { OrderGateway } from "../../src/orderGateway/OrderGateway.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract OrderGatewayHarness is OrderGateway {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_ORDER_GATEWAY_STORAGE_LOCATION() external view returns (bytes32) {
        return _ORDER_GATEWAY_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract OrderGatewayStorageSpec is BaseTest, ERC7201Location {
    OrderGatewayHarness public orderGatewayHarness;

    function setUp() public {
        orderGatewayHarness = new OrderGatewayHarness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            orderGatewayHarness.exposed_ORDER_GATEWAY_STORAGE_LOCATION(),
            getLocation("perp.storage.orderGateway")
        );
    }
}
