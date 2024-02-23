// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";

abstract contract AddressResolverUpgradeable is Initializable {
    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.addressResolver
    struct AddressResolverStorage {
        address addressManager;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.addressResolver")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _ADDRESS_RESOLVER_STORAGE_LOCATION =
        0x4f06a8acb33e9b8049350b52d709cac2a4fafaec3fef942cdcdff92c2f60d000;

    //
    // INIT
    //

    /**
     * @param addressManager_ Address of the AddressManager.
     */

    // solhint-disable-func-name-mixedcase
    function __AddressResolver_init(address addressManager_) internal onlyInitializing {
        __AddressResolver_init_unchained(addressManager_);
    }

    // solhint-disable-func-name-mixedcase
    function __AddressResolver_init_unchained(address addressManager_) internal onlyInitializing {
        _getAddressResolverStorage().addressManager = addressManager_;
    }

    //
    // PUBLIC
    //

    function getAddressManager() public view returns (IAddressManager) {
        return IAddressManager(_getAddressResolverStorage().addressManager);
    }

    //
    // PRIVATE
    //

    function _getAddressResolverStorage() private pure returns (AddressResolverStorage storage $) {
        assembly {
            $.slot := _ADDRESS_RESOLVER_STORAGE_LOCATION
        }
    }
}
