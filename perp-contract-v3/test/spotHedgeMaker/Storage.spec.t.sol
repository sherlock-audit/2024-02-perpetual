// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "../../src/common/LibConstant.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract SpotHedgeBaseMakerHarness is SpotHedgeBaseMaker {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_SPOT_HEDGE_BASE_MAKER_STORAGE_LOCATION() external view returns (bytes32) {
        return _SPOT_HEDGE_BASE_MAKER_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract SpotHedgeBaseMakerStorageSpec is BaseTest, ERC7201Location {
    SpotHedgeBaseMakerHarness public spotHedgeBaseMakerHarness;

    function setUp() public {
        spotHedgeBaseMakerHarness = new SpotHedgeBaseMakerHarness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            spotHedgeBaseMakerHarness.exposed_SPOT_HEDGE_BASE_MAKER_STORAGE_LOCATION(),
            getLocation("perp.storage.spotHedgeBaseMaker")
        );
    }
}
