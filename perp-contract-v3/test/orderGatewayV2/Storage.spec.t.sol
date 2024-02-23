// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "../../src/common/LibConstant.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { OrderGatewayV2 } from "../../src/orderGatewayV2/OrderGatewayV2.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract OrderGatewayV2Harness is OrderGatewayV2 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_ORDER_GATEWAY_V2_STORAGE_LOCATION() external view returns (bytes32) {
        return _ORDER_GATEWAY_V2_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract OrderGatewayV2StorageSpec is BaseTest, ERC7201Location {
    OrderGatewayV2Harness public orderGatewayV2Harness;

    function setUp() public {
        orderGatewayV2Harness = new OrderGatewayV2Harness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            orderGatewayV2Harness.exposed_ORDER_GATEWAY_V2_STORAGE_LOCATION(),
            getLocation("perp.storage.orderGatewayV2")
        );
    }
}
