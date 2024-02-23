// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibError } from "../common/LibError.sol";

interface IFundModelEvent {
    event FundChanged(address indexed trader, int256 fundDelta);
}

/// @dev the only entry point to get & set fund
/// @dev the only place to emit IFundModelEvent
abstract contract FundModelUpgradeable is Initializable, IFundModelEvent {
    using FixedPointMathLib for int256;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.fundModel
    struct FundModelStorage {
        // key: trader
        mapping(address => uint256) fundMap;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.fundModel")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _FUND_MODEL_STORAGE_LOCATION = 0xc0fee89fe051f94c5238bcc7d7bce407cd8fbba9246b09ff5d1f693358b1f800;

    //
    // INIT
    //
    function __FundModel_init() internal onlyInitializing {}

    //
    // INTERNAL
    //
    function _updateFund(address trader, int256 fundDeltaXCD) internal {
        uint256 fundDeltaAbsXCD = fundDeltaXCD.abs();
        FundModelStorage storage $ = _getFundModelStorage();
        if (fundDeltaXCD >= 0) {
            $.fundMap[trader] += fundDeltaAbsXCD;
        } else {
            // when fundDelta is negative (withdraw), check if trader has enough fund
            if ($.fundMap[trader] < fundDeltaAbsXCD) {
                revert LibError.InsufficientFund(trader, $.fundMap[trader], fundDeltaXCD);
            }

            $.fundMap[trader] -= fundDeltaAbsXCD;
        }

        emit FundChanged(trader, fundDeltaXCD);
    }

    function _getFund(address trader) internal view returns (uint256) {
        return _getFundModelStorage().fundMap[trader];
    }

    //
    // PRIVATE
    //

    function _getFundModelStorage() private pure returns (FundModelStorage storage $) {
        assembly {
            $.slot := _FUND_MODEL_STORAGE_LOCATION
        }
    }
}
