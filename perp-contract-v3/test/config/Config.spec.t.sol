// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { BaseTest } from "../BaseTest.sol";
import { Config } from "../../src/config/Config.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";
import "../MockSetup.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ConfigHarness is Config {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_CONFIG_STORAGE_LOCATION() external view returns (bytes32) {
        return _CONFIG_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract ConfigTest is MockSetup, ERC7201Location {
    ConfigHarness public configHarness;

    Config config = new Config();
    address public nonAdmin = makeAddr("nonAdmin");

    function setUp() public virtual override {
        MockSetup.setUp();
        _enableInitialize(address(config));
        config.initialize(mockAddressManager);
        configHarness = new ConfigHarness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(configHarness.exposed_CONFIG_STORAGE_LOCATION(), getLocation("perp.storage.config"));
    }

    function test_SetMaxOrderValidDuration() public {
        vm.expectEmit(true, true, true, true, address(config));
        emit Config.MaxOrderValidDurationSet(1, 0);

        config.setMaxOrderValidDuration(1);
        assertEq(config.getMaxOrderValidDuration(), 1);
    }

    function test_SetInitialMarginRatio() public {
        vm.expectEmit(true, true, true, true, address(config));
        emit Config.InitialMarginRatioSet(marketId, 0.15e18, 0);

        config.setInitialMarginRatio(marketId, 0.15e18);
        assertEq(config.getInitialMarginRatio(marketId), 0.15e18);
    }

    function test_SetMaintenanceMarginRatio() public {
        vm.expectEmit(true, true, true, true, address(config));
        emit Config.MaintenanceMarginRatioSet(marketId, 0.1e18, 0);

        config.setMaintenanceMarginRatio(marketId, 0.1e18);
        assertEq(config.getMaintenanceMarginRatio(marketId), 0.1e18);
    }

    function test_SetLiquidationFeeRatio() public {
        vm.expectEmit(true, true, true, true, address(config));
        emit Config.LiquidationFeeRatioSet(marketId, 0.1e18, 0);

        config.setLiquidationFeeRatio(marketId, 0.1e18);
        assertEq(config.getLiquidationFeeRatio(marketId), 0.1e18);
    }

    function test_SetLiquidationPenaltyRatio() public {
        vm.expectEmit(true, true, true, true, address(config));
        emit Config.LiquidationPenaltyRatioSet(marketId, 0.1e18, 0);

        config.setLiquidationPenaltyRatio(marketId, 0.1e18);
        assertEq(config.getLiquidationPenaltyRatio(marketId), 0.1e18);
    }

    function test_setMaxBorrowingFeeRate() public {
        vm.expectCall(
            address(mockBorrowingFee),
            abi.encodeWithSelector(IBorrowingFee.setMaxBorrowingFeeRate.selector, marketId, 0.1e18, 0.1e18)
        );
        config.setMaxBorrowingFeeRate(marketId, 0.1e18, 0.1e18);
    }

    function test_setDepositCap() public {
        vm.expectEmit(true, true, true, true, address(config));
        emit Config.DepositCapSet(100e6, 0);

        config.setDepositCap(100e6);
    }

    function test_RegisterMaker() public {
        address newMaker = makeAddr("newMaker");

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getPositionSize.selector, marketId, newMaker),
            abi.encode(0)
        );

        vm.expectEmit(true, true, true, true, address(config));
        emit Config.MakerRegistered(marketId, newMaker);

        config.registerMaker(marketId, newMaker);
    }

    function test_SetInitialMarginRatio_RevertIf_InvalidRatio() public {
        uint256 invalidRatio = 1e18 + 1;
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidRatio.selector, invalidRatio));
        config.setInitialMarginRatio(marketId, invalidRatio);
    }

    function test_SetMaintenanceMarginRatio_RevertIf_InvalidRatio() public {
        uint256 invalidRatio = 1e18 + 1;
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidRatio.selector, invalidRatio));
        config.setMaintenanceMarginRatio(marketId, invalidRatio);
    }

    function test_SetLiquidationFeeRatio_RevertIf_InvalidRatio() public {
        uint256 invalidRatio = 1e18 + 1;
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidRatio.selector, invalidRatio));
        config.setLiquidationFeeRatio(marketId, invalidRatio);
    }

    function test_SetLiquidationPenaltyRatio_RevertIf_InvalidRatio() public {
        uint256 invalidRatio = 1e18 + 1;
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidRatio.selector, invalidRatio));
        config.setLiquidationPenaltyRatio(marketId, invalidRatio);
    }

    function test_RegisterMaker_RevertIf_ZeroAddress() public {
        vm.expectRevert(LibError.ZeroAddress.selector);
        config.registerMaker(marketId, address(0));
    }

    function test_RegisterMaker_RevertIf_MakerExists() public {
        address maker = makeAddr("maker");

        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getPositionSize.selector, marketId, maker), abi.encode(0));

        config.registerMaker(marketId, maker);

        // should revert when set same maker again
        vm.expectRevert(abi.encodeWithSelector(LibError.MakerExists.selector, marketId, maker));
        config.registerMaker(marketId, maker);
    }

    function test_RegisterMaker_RevertIf_MakerHasPosition() public {
        address maker = makeAddr("maker");

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getPositionSize.selector, marketId, maker),
            abi.encode(1 ether)
        );

        vm.expectRevert(abi.encodeWithSelector(LibError.MakerHasPosition.selector, marketId, maker, 1 ether));
        config.registerMaker(marketId, maker);
    }

    function test_RevertIf_NotOwnerWhenSettingMaxOrderValidDuration() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setMaxOrderValidDuration(1);
    }

    function test_RevertIf_NotOwnerWhenSettingInitialMarginRatio() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setInitialMarginRatio(marketId, 1);
    }

    function test_RevertIf_NotOwnerWhenSettingMaintenanceMarginRatio() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setMaintenanceMarginRatio(marketId, 1);
    }

    function test_RevertIf_NotOwnerWhenSettingLiquidationFeeRatio() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setLiquidationFeeRatio(marketId, 1);
    }

    function test_RevertIf_NotOwnerWhenSettingLiquidationPenaltyRatio() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setLiquidationPenaltyRatio(marketId, 1);
    }

    function test_RevertIf_NotOwnerWhenSettingTargetBorrowingFeeRate() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setMaxBorrowingFeeRate(marketId, 1, 1);
    }

    function test_RevertIf_NotOwnerWhenSettingDepositCap() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonAdmin));
        vm.prank(nonAdmin);
        config.setDepositCap(100e6);
    }
}
