// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

library LibMargin {
    using SafeCast for int256;
    using SafeCast for uint256;
    using FixedPointMathLib for int256;

    /// @dev in another word it's margin without pending margin
    function getSettledMargin(uint256 marginState, int256 unsettledPnl) internal pure returns (int256) {
        return marginState.toInt256() + unsettledPnl;
    }

    /// @dev free margin = max(margin state + pending margin + settleable unsettled pnl, 0)
    function getFreeMargin(
        uint256 marginState,
        int256 pendingMargin,
        int256 unsettledPnl,
        uint256 pnlPoolBalance
    ) internal pure returns (uint256) {
        int256 freeMargin = marginState.toInt256();
        unsettledPnl += pendingMargin;

        // calculate settleableUnsettledPnl
        int256 settleableUnsettledPnl;
        if (unsettledPnl > 0) {
            // when there's unsettled profit, pnl pool pays as much as it can
            // if unsettled profit >= pnl pool, pnl pool pay 100% balance
            // if pnl pool >= unsettled profit, pnl pay 100% unsettled profit
            settleableUnsettledPnl = FixedPointMathLib.min(unsettledPnl, pnlPoolBalance.toInt256());
        } else if (unsettledPnl < 0) {
            // if margin is negative, ignore
            if (freeMargin <= 0) {
                return 0;
            }

            // else when margin is positive
            // when there's unsettled loss, trader pays as much as it has (from margin):
            uint256 unsettledLoss = unsettledPnl.abs();
            uint256 positiveMargin = freeMargin.abs();
            if (unsettledLoss >= positiveMargin) {
                // if unsettled loss >= margin, pay 100% margin, margin goes to 0
                return 0;
            }

            // else: if margin > unsettled loss, margin pay 100% unsettled loss
            settleableUnsettledPnl = unsettledPnl;
        }

        // calculate margin
        freeMargin += settleableUnsettledPnl;
        if (freeMargin < 0) {
            return 0;
        }
        return freeMargin.toUint256();
    }
}
