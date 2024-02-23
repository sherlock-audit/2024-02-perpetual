// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "../../src/common/LibConstant.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { AddressResolverUpgradeable } from "../../src/addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../../src/addressResolver/LibAddressResolver.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract AddressResolverHarness is AddressResolverUpgradeable {
    using LibAddressResolver for IAddressManager;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) external initializer {
        __AddressResolver_init(addressManager);
    }

    function exposed_getVault() external view returns (address) {
        return address(getAddressManager().getVault());
    }

    function exposed_getClearingHouse() external view returns (address) {
        return address(getAddressManager().getClearingHouse());
    }

    function exposed_getBorrowingFee() external view returns (address) {
        return address(getAddressManager().getBorrowingFee());
    }

    function exposed_getOrderGateway() external view returns (address) {
        return address(getAddressManager().getOrderGateway());
    }

    function exposed_getOracleAdapter() external view returns (address) {
        return address(getAddressManager().getPythOracleAdapter());
    }

    function exposed_ADDRESS_RESOLVER_STORAGE_LOCATION() external view returns (bytes32) {
        return _ADDRESS_RESOLVER_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract AddressResolverInt is BaseTest, ERC7201Location {
    AddressManager public addressManager;
    AddressResolverHarness public addressResolverHarness;

    address public vault = makeAddr("Vault");
    address public clearingHouse = makeAddr("ClearingHouse");
    address public borrowingFee = makeAddr("BorrowingFee");
    address public orderGateway = makeAddr("OrderGateway");
    address public pythOracleAdapter = makeAddr("PythOracleAdapter");

    function setUp() public {
        addressManager = new AddressManager();

        addressResolverHarness = new AddressResolverHarness();
        _enableInitialize(address(addressResolverHarness));
        addressResolverHarness.initialize(address(addressManager));

        addressManager.setAddress(VAULT, vault);
        addressManager.setAddress(CLEARING_HOUSE, clearingHouse);
        addressManager.setAddress(BORROWING_FEE, borrowingFee);
        addressManager.setAddress(ORDER_GATEWAY, orderGateway);
        addressManager.setAddress(PYTH_ORACLE_ADAPTER, pythOracleAdapter);
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            addressResolverHarness.exposed_ADDRESS_RESOLVER_STORAGE_LOCATION(),
            getLocation("perp.storage.addressResolver")
        );
    }

    function test_getVault() public {
        assertEq(addressResolverHarness.exposed_getVault(), vault);
    }

    function test_getVault_when_set_new_address() public {
        address newVault = makeAddr("NewVault");
        addressManager.setAddress(VAULT, newVault);
        assertEq(addressResolverHarness.exposed_getVault(), newVault);
    }

    function test_getClearingHouse() public {
        assertEq(addressResolverHarness.exposed_getClearingHouse(), clearingHouse);
    }

    function test_getClearingHouse_when_set_new_address() public {
        address newClearingHouse = makeAddr("NewClearingHouse");
        addressManager.setAddress(CLEARING_HOUSE, newClearingHouse);
        assertEq(addressResolverHarness.exposed_getClearingHouse(), newClearingHouse);
    }

    function test_getBorrowingFee() public {
        assertEq(addressResolverHarness.exposed_getBorrowingFee(), borrowingFee);
    }

    function test_getBorrowingFee_when_set_new_address() public {
        address newBorrowingFee = makeAddr("NewBorrowingFee");
        addressManager.setAddress(BORROWING_FEE, newBorrowingFee);
        assertEq(addressResolverHarness.exposed_getBorrowingFee(), newBorrowingFee);
    }

    function test_getOrderGateway() public {
        assertEq(addressResolverHarness.exposed_getOrderGateway(), orderGateway);
    }

    function test_getOrderGateway_when_set_new_address() public {
        address newOrderGateway = makeAddr("NewOrderGateway");
        addressManager.setAddress(ORDER_GATEWAY, newOrderGateway);
        assertEq(addressResolverHarness.exposed_getOrderGateway(), newOrderGateway);
    }

    function test_getOracleAdapter() public {
        assertEq(addressResolverHarness.exposed_getOracleAdapter(), pythOracleAdapter);
    }

    function test_getOracleAdapter_when_set_new_address() public {
        address newOracleAdapter = makeAddr("NewOracleAdapter");
        addressManager.setAddress(PYTH_ORACLE_ADAPTER, newOracleAdapter);
        assertEq(addressResolverHarness.exposed_getOracleAdapter(), newOracleAdapter);
    }
}
