// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;
pragma abicoder v2;

import { CircuitBreaker } from "../../src/circuitBreaker/CircuitBreaker.sol";
import { LibError } from "../../src/common/LibError.sol";

import "forge-std/Test.sol";

contract CircuitBreakerAdminSpec is Test {
    CircuitBreaker circuitBreaker;

    address admin = makeAddr("admin");
    address nonAdmin = makeAddr("nonAdmin");
    address collateralToken = makeAddr("collateralToken");
    address vault = makeAddr("vault");

    function setUp() public {
        // _rateLimitCooldownPeriod
        // _withdrawalPeriod
        // _liquidityTickLength
        circuitBreaker = new CircuitBreaker(admin, 3 days, 4 hours, 5 minutes);
    }

    function test_RevertIf_RegisterAssetNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.registerAsset(collateralToken, 7000, 0);
    }

    function test_RevertIf_UpdateAssetParamsNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.updateAssetParams(collateralToken, 7000, 0);
    }

    function test_RevertIf_OverrideRateLimitNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.overrideRateLimit();
    }

    function test_RevertIf_AddProtectedContractsNotAdmin() public {
        address[] memory protectedContracts = new address[](1);
        protectedContracts[0] = vault;

        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.addProtectedContracts(protectedContracts);
    }

    function test_RevertIf_RemoveProtectedContractsNotAdmin() public {
        address[] memory protectedContracts = new address[](1);
        protectedContracts[0] = vault;

        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.removeProtectedContracts(protectedContracts);
    }

    function test_RevertIf_StartGracePeriodNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.startGracePeriod(block.timestamp + 1 days);
    }

    function test_RevertIf_SetAdminNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.setAdmin(nonAdmin);
    }

    function test_RevertIf_MarkAsNotOperationalNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.markAsNotOperational();
    }

    function test_RevertIf_MigrateFundsAfterExploitNotAdmin() public {
        address[] memory assets = new address[](1);
        assets[0] = collateralToken;

        vm.prank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAdmin.selector));
        circuitBreaker.migrateFundsAfterExploit(assets, nonAdmin);
    }
}
