// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ContextBase } from "../common/ContextBase.sol";
import { IAuthorization } from "./IAuthorization.sol";

abstract contract AuthorizationUpgradeable is Initializable, ContextBase, IAuthorization {
    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.authorization
    struct AuthorizationStorage {
        // authorizer => authorized
        mapping(address => mapping(address => bool)) isAuthorized;
    }

    //
    // EVENT
    //
    event AuthorizationSet(address indexed authorizer, address indexed authorized, bool isAuthorized);

    //
    // ERROR
    //
    error AuthorizationAlreadySet();

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.authorization")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _AUTHORIZATION_STORAGE_LOCATION =
        0x51306e4512d35d374c736bfa30fc78b9c97fabb28fe92ec8451c42d8596a5300;

    //
    // INIT
    //
    function __Authorization_init() internal onlyInitializing {}

    //
    // EXTERNAL
    //

    /// @dev when sender use Multicaller to call this contract, authorizer is the sender, not Multicaller
    function setAuthorization(address authorizedArg, bool isAuthorized_) public virtual override {
        address sender = _sender();
        if (isAuthorized_ == _getAuthorizationStorage().isAuthorized[sender][authorizedArg])
            revert AuthorizationAlreadySet();
        _getAuthorizationStorage().isAuthorized[sender][authorizedArg] = isAuthorized_;
        emit AuthorizationSet(sender, authorizedArg, isAuthorized_);
    }

    function isAuthorized(address authorizer, address authorized) public view virtual override returns (bool) {
        return authorizer == authorized || _getAuthorizationStorage().isAuthorized[authorizer][authorized];
    }

    //
    // PRIVATE
    //

    function _getAuthorizationStorage() private pure returns (AuthorizationStorage storage $) {
        assembly {
            $.slot := _AUTHORIZATION_STORAGE_LOCATION
        }
    }
}
