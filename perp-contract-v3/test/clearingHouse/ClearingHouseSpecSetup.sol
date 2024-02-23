// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../MockSetup.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { BaseTest } from "../BaseTest.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { Config } from "../../src/config/Config.sol";
import { SystemStatus } from "../../src/systemStatus/SystemStatus.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";

contract ClearingHouseSpecSetup is MockSetup {
    ClearingHouse public clearingHouse;
    address public taker = makeAddr("taker");

    function setUp() public virtual override {
        MockSetup.setUp();

        clearingHouse = new ClearingHouse();
        _enableInitialize(address(clearingHouse));
        clearingHouse.initialize(mockAddressManager);

        // override mock to replace mockClearingHouse
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, CLEARING_HOUSE),
            abi.encode(clearingHouse)
        );

        // mock SystemStatus to be active
        address mockedSystemStatus = makeAddr("mockedSystemStatus");
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, "SystemStatus"),
            abi.encode(mockedSystemStatus)
        );
        vm.mockCall(mockedSystemStatus, abi.encodeWithSelector(SystemStatus.requireSystemActive.selector), "");
        vm.mockCall(
            mockedSystemStatus,
            abi.encodeWithSelector(SystemStatus.requireMarketActive.selector, marketId),
            ""
        );

        // mock CircuitBreaker to be deactivate
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, "CircuitBreaker"),
            abi.encode(address(0))
        );
    }

    function _mockVaultPosition(
        address trader,
        uint256 freeMargin,
        int256 margin,
        int256 size,
        int256 openNotional
    ) internal {
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getMargin.selector, marketId, trader), abi.encode(margin));
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getFreeMargin.selector, marketId, trader),
            abi.encode(freeMargin)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getPositionSize.selector, marketId, trader),
            abi.encode(size)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader),
            abi.encode(openNotional)
        );
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
