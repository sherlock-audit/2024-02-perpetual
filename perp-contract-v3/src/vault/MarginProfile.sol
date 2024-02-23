// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { WAD } from "../common/LibConstant.sol";
import { IMarginProfile, MarginRequirementType } from "./IMarginProfile.sol";

abstract contract MarginProfile is IMarginProfile {
    using SafeCast for uint256;
    using SafeCast for int256;
    using FixedPointMathLib for int256;

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IMarginProfile
    function getMarginRatio(uint256 marketId, address trader, uint256 price) external view returns (int256) {
        int256 openNotional = getOpenNotional(marketId, trader);
        if (openNotional == 0) {
            return type(int256).max;
        }
        int256 accountValue = getAccountValue(marketId, trader, price);
        return (accountValue * WAD.toInt256()) / openNotional.abs().toInt256();
    }

    /// @inheritdoc IMarginProfile
    function getFreeCollateral(uint256 marketId, address trader, uint256 price) public view returns (uint256) {
        int256 accountValue = getAccountValue(marketId, trader, price);
        if (accountValue <= 0) {
            return 0;
        }

        uint256 freeMargin = getFreeMargin(marketId, trader);
        uint256 initialMarginRequirement = getMarginRequirement(marketId, trader, MarginRequirementType.INITIAL);
        uint256 minOfFreeMarginAndAccountValue = FixedPointMathLib.min(freeMargin, accountValue.toUint256());
        if (initialMarginRequirement >= minOfFreeMarginAndAccountValue) {
            return 0;
        }
        return minOfFreeMarginAndAccountValue - initialMarginRequirement;
    }

    /// @inheritdoc IMarginProfile
    function getFreeCollateralForTrade(
        uint256 marketId,
        address trader,
        uint256 price,
        MarginRequirementType marginRequirementType
    ) external view returns (int256) {
        int256 margin = getMargin(marketId, trader);
        int256 accountValue = getAccountValue(marketId, trader, price);
        uint256 marginRequirement = getMarginRequirement(marketId, trader, marginRequirementType);
        int256 minOfMarginAndAccountValue = FixedPointMathLib.min(margin, accountValue);
        return minOfMarginAndAccountValue - marginRequirement.toInt256();
    }

    //
    // PUBLIC VIEW
    //

    /// @inheritdoc IMarginProfile
    function getMarginRequirement(
        uint256 marketId,
        address trader,
        MarginRequirementType marginRequirementType
    ) public view returns (uint256) {
        uint256 requiredMarginRatio;
        if (marginRequirementType == MarginRequirementType.INITIAL) {
            requiredMarginRatio = _getInitialMarginRatio(marketId);
        } else if (marginRequirementType == MarginRequirementType.MAINTENANCE) {
            requiredMarginRatio = _getMaintenanceMarginRatio(marketId);
        } else {
            assert(false);
        }
        int256 openNotional = getOpenNotional(marketId, trader);
        return ((openNotional.abs() * requiredMarginRatio) / WAD);
    }

    /// @inheritdoc IMarginProfile
    function getUnrealizedPnl(uint256 marketId, address trader, uint256 price) public view returns (int256) {
        int256 openNotional = getOpenNotional(marketId, trader);
        return _getPositionValue(marketId, trader, price) + openNotional;
    }

    /// @inheritdoc IMarginProfile
    function getAccountValue(uint256 marketId, address trader, uint256 price) public view returns (int256) {
        return getMargin(marketId, trader) + getUnrealizedPnl(marketId, trader, price);
    }

    //
    // VIRTUAL PUBLIC VIEW
    //

    /// @inheritdoc IMarginProfile
    function getMargin(uint256 marketId, address trader) public view virtual returns (int256);

    /// @inheritdoc IMarginProfile
    function getFreeMargin(uint256 marketId, address trader) public view virtual returns (uint256);

    /// @inheritdoc IMarginProfile
    function getOpenNotional(uint256 marketId, address trader) public view virtual returns (int256);

    /// @inheritdoc IMarginProfile
    function getPositionSize(uint256 marketId, address trader) public view virtual returns (int256);

    //
    // INTERNAL VIEW
    //

    /// @notice position value = position size * price
    function _getPositionValue(uint256 marketId, address trader, uint256 price) internal view returns (int256) {
        // NOTE: if any of the following formula changed, we should also check OracleMaker.getPositionRate()
        int256 positionSize = getPositionSize(marketId, trader);
        return ((positionSize * price.toInt256()) / WAD.toInt256());
    }

    //
    // VIRTUAL INTERNAL VIEW
    //
    function _getInitialMarginRatio(uint256 marketId) internal view virtual returns (uint256);

    function _getMaintenanceMarginRatio(uint256 marketId) internal view virtual returns (uint256);
}
