// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibLugiaMath } from "../common/LugiaMath.sol";
import { Position } from "./PositionModelStruct.sol";

library LibPosition {
    using SafeCast for uint256;
    using FixedPointMathLib for int256;
    using LibPosition for Position;

    /// @notice update both positionSize and openNotional
    /// @return realizedPnl
    function add(Position storage self, int256 positionSizeDelta, int256 openNotionalDelta) internal returns (int256) {
        int256 openNotional = self.openNotional;
        int256 positionSize = self.positionSize;

        bool isLong = positionSizeDelta > 0;
        int256 realizedPnl = 0;

        // new or increase position
        if (positionSize == 0 || (positionSize > 0 && isLong) || (positionSize < 0 && !isLong)) {
            // no old pos size = new position
            // direction is same as old pos = increase position
        } else {
            // openNotionalDelta and oldOpenNotional have different signs = reduce, close or reverse position
            // check if it's reduce or close by comparing absolute position size
            // if reduce
            // realizedPnl = oldOpenNotional * closedRatio + openNotionalDelta
            // closedRatio = positionSizeDeltaAbs / positionSizeAbs
            // if close and increase reverse position
            // realizedPnl = oldOpenNotional + openNotionalDelta * closedPositionSize / positionSizeDelta
            uint256 positionSizeDeltaAbs = positionSizeDelta.abs();
            uint256 positionSizeAbs = positionSize.abs();

            if (positionSizeAbs >= positionSizeDeltaAbs) {
                // reduce or close position
                int256 reducedOpenNotional = (openNotional * positionSizeDeltaAbs.toInt256()) /
                    positionSizeAbs.toInt256();
                realizedPnl = reducedOpenNotional + openNotionalDelta;
            } else {
                // open reverse position
                realizedPnl =
                    openNotional +
                    (openNotionalDelta * positionSizeAbs.toInt256()) /
                    positionSizeDeltaAbs.toInt256();
            }
        }

        self.positionSize += positionSizeDelta;
        self.openNotional += openNotionalDelta - realizedPnl;

        return realizedPnl;
    }

    function updateMargin(Position storage self, int256 delta) internal {
        self.margin = LibLugiaMath.applyDelta(self.margin, delta);
    }

    //
    // PURE
    //

    /// @notice Reverse position (eg. long 1 -> short 1) is not reduce only
    function isReduceOnly(int256 positionSizeBefore, int256 positionSizeAfter) internal pure returns (bool) {
        if (positionSizeAfter != 0 && positionSizeBefore ^ positionSizeAfter < 0) {
            return false;
        }
        return positionSizeBefore.abs() > positionSizeAfter.abs();
    }

    function isIncreasing(int256 positionSizeBefore, int256 positionSizeDelta) internal pure returns (bool) {
        bool isOldPositionLong = positionSizeBefore > 0;
        bool isLong = positionSizeDelta > 0;
        return positionSizeBefore == 0 || (isOldPositionLong && isLong) || (!isOldPositionLong && !isLong);
    }
}
