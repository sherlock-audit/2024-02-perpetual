// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "../../src/common/LibConstant.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { AuthorizationUpgradeable } from "../../src/authorization/AuthorizationUpgradeable.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract AuthorizationHarness is AuthorizationUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_AUTHORIZATION_STORAGE_LOCATION() external view returns (bytes32) {
        return _AUTHORIZATION_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract AuthorizationSpec is BaseTest, ERC7201Location {
    AuthorizationHarness public authorizationHarness;

    function setUp() public {
        authorizationHarness = new AuthorizationHarness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            authorizationHarness.exposed_AUTHORIZATION_STORAGE_LOCATION(),
            getLocation("perp.storage.authorization")
        );
    }
}
