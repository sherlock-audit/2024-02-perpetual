// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

/* External Imports */
// solhint-disable-next-line max-line-length
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ISystemStatus } from "./ISystemStatus.sol";
import { LibError } from "../common/LibError.sol";

contract SystemStatus is ISystemStatus, Ownable2StepUpgradeable {
    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.systemStatus
    struct SystemStatusStorage {
        bool systemSuspended;
        mapping(uint256 => bool) marketSuspendedMap;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.systemStatus")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _SYSTEM_STATUS_STORAGE_LOCATION =
        0x3161897ffab7c7277468dc6d89c699aa4b712116dd286423a618ad5033208500;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
    }

    function suspendSystem() external onlyOwner {
        _getSystemStatusStorage().systemSuspended = true;
        emit SystemSuspended();
    }

    function resumeSystem() external onlyOwner {
        _getSystemStatusStorage().systemSuspended = false;
        emit SystemResumed();
    }

    function suspendMarket(uint256 marketId) external onlyOwner {
        _getSystemStatusStorage().marketSuspendedMap[marketId] = true;
        emit MarketSuspended(marketId);
    }

    function resumeMarket(uint256 marketId) external onlyOwner {
        _getSystemStatusStorage().marketSuspendedMap[marketId] = false;
        emit MarketResumed(marketId);
    }

    //
    // EXTERNAL VIEW
    //

    function systemSuspended() external view returns (bool) {
        return _getSystemStatusStorage().systemSuspended;
    }

    function marketSuspendedMap(uint256 marketId) external view returns (bool) {
        return _getSystemStatusStorage().marketSuspendedMap[marketId];
    }

    function requireSystemActive() external view {
        _requireSystemActive();
    }

    function requireMarketActive(uint256 marketId) external view {
        _requireSystemActive();
        _requireMarketActive(marketId);
    }

    //
    // INTERNAL VIEW
    //

    function _requireSystemActive() internal view {
        if (_getSystemStatusStorage().systemSuspended) revert LibError.SystemIsSuspended();
    }

    function _requireMarketActive(uint256 marketId) internal view {
        if (_getSystemStatusStorage().marketSuspendedMap[marketId]) revert LibError.MarketIsSuspended(marketId);
    }

    //
    // PRIVATE
    //

    function _getSystemStatusStorage() private pure returns (SystemStatusStorage storage $) {
        assembly {
            $.slot := _SYSTEM_STATUS_STORAGE_LOCATION
        }
    }
}
