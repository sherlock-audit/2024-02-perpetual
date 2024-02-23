// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { BaseTest } from "../BaseTest.sol";
import { SystemStatus } from "../../src/systemStatus/SystemStatus.sol";
import { ISystemStatus } from "../../src/systemStatus/ISystemStatus.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SystemStatusHarness is SystemStatus {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_SYSTEM_STATUS_STORAGE_LOCATION() external view returns (bytes32) {
        return _SYSTEM_STATUS_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract SystemStatusTest is BaseTest, ERC7201Location {
    SystemStatusHarness public systemStatusHarness;

    uint256 private marketId = 1;

    SystemStatus private systemStatus = new SystemStatus();
    address private nonAdmin = makeAddr("nonAdmin");

    function setUp() public {
        _enableInitialize(address(systemStatus));
        systemStatus.initialize();

        systemStatusHarness = new SystemStatusHarness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            systemStatusHarness.exposed_SYSTEM_STATUS_STORAGE_LOCATION(),
            getLocation("perp.storage.systemStatus")
        );
    }

    function test_SuspendSystem() public {
        vm.expectEmit(true, true, true, true);
        emit ISystemStatus.SystemSuspended();
        systemStatus.suspendSystem();
        assertTrue(systemStatus.systemSuspended());

        vm.expectRevert(LibError.SystemIsSuspended.selector);
        systemStatus.requireSystemActive();

        vm.expectRevert(LibError.SystemIsSuspended.selector);
        systemStatus.requireMarketActive(marketId);
    }

    function test_ResumeSystem() public {
        systemStatus.suspendSystem();
        assertTrue(systemStatus.systemSuspended());

        vm.expectEmit(true, true, true, true);
        emit ISystemStatus.SystemResumed();
        systemStatus.resumeSystem();
        assertFalse(systemStatus.systemSuspended());

        // not revert when require market active or system active
        systemStatus.requireSystemActive();
        systemStatus.requireMarketActive(marketId);
    }

    function test_SuspendMarket() public {
        vm.expectEmit(true, true, true, true);
        emit ISystemStatus.MarketSuspended(marketId);
        systemStatus.suspendMarket(marketId);
        assertTrue(systemStatus.marketSuspendedMap(marketId));

        vm.expectRevert(abi.encodeWithSelector(LibError.MarketIsSuspended.selector, marketId));
        systemStatus.requireMarketActive(marketId);

        // not revert when require system active
        systemStatus.requireSystemActive();
    }

    function test_ResumeMarket() public {
        systemStatus.suspendMarket(marketId);
        assertTrue(systemStatus.marketSuspendedMap(marketId));

        vm.expectEmit(true, true, true, true);
        emit ISystemStatus.MarketResumed(marketId);
        systemStatus.resumeMarket(marketId);
        assertFalse(systemStatus.marketSuspendedMap(marketId));

        // not revert when require market active or system active
        systemStatus.requireSystemActive();
        systemStatus.requireMarketActive(marketId);
    }

    function test_RevertIf_NonOwner() public {
        vm.startPrank(nonAdmin);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        systemStatus.suspendSystem();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        systemStatus.resumeSystem();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        systemStatus.suspendMarket(marketId);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        systemStatus.resumeMarket(marketId);
    }
}
