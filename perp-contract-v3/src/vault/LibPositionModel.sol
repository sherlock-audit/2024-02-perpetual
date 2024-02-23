// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibLugiaMath } from "../common/LugiaMath.sol";
import { LibPosition } from "./LibPosition.sol";
import { PositionModelState, Position } from "./PositionModelStruct.sol";

library LibPositionModel {
    using SafeCast for int256;
    using SafeCast for uint256;
    using FixedPointMathLib for int256;
    using LibPositionModel for PositionModelState;
    using LibPosition for Position;

    /// @notice update both unsettledPnl and pnlPoolBalance
    /// @return settledPnl
    function settlePnl(PositionModelState storage self, address trader, int256 realizedPnl) internal returns (int256) {
        Position storage position = self.positionMap[trader];
        uint256 remainPnlPoolBalance = self.pnlPoolBalance;

        //
        // In-memory calculation.
        //
        int256 oldUnsettledPnl = position.unsettledPnl;
        if (oldUnsettledPnl == 0 && realizedPnl == 0) {
            // No-op.
            return 0;
        }

        // pnlToSettle in trader's perspective
        int256 pnlToSettle = oldUnsettledPnl + realizedPnl;
        int256 newUnsettledPnl = 0;
        int256 settledPnl = 0;
        // Settle if possible
        //   - pnlToSettle > 0 && pnlToSettle > PnlPool       -> Settle as much as possible using all the PnL Pool
        //   - pnlToSettle > 0 && pnlToSettle <= PnlPool      -> PnL Pool has enough to pay all unsettled PnL
        //   - pnlToSettle < 0 && abs(pnlToSettle) > margin   -> Settle as much as possible using all the margin
        //   - pnlToSettle < 0 && abs(pnlToSettle) <= margin  -> Margin has enough to pay all unsettled PnL
        if (pnlToSettle > 0) {
            // Take from pnl pool
            if (pnlToSettle.toUint256() > remainPnlPoolBalance) {
                // Settle as much as possible using all the PnL Pool.
                newUnsettledPnl = pnlToSettle - remainPnlPoolBalance.toInt256();
                settledPnl = remainPnlPoolBalance.toInt256();
                remainPnlPoolBalance = 0;
            } else {
                // PnL Pool has enough to pay all unsettled PnL
                newUnsettledPnl = 0;
                settledPnl = pnlToSettle;
                remainPnlPoolBalance -= settledPnl.toUint256();
            }
        } else {
            // pnlToSettle < 0, pay to pnl pool
            settledPnl = -(FixedPointMathLib.min(position.margin, pnlToSettle.abs())).toInt256();
            newUnsettledPnl = pnlToSettle - settledPnl;
            remainPnlPoolBalance += settledPnl.abs();
        }

        // update position
        position.unsettledPnl = newUnsettledPnl;
        // update pnl pool
        self.pnlPoolBalance = remainPnlPoolBalance;

        return settledPnl;
    }

    /// @return delta
    function updateBadDebt(
        PositionModelState storage self,
        int256 oldUnsettledPnl,
        int256 newUnsettledPnl
    ) internal returns (int256) {
        int256 delta;
        if (newUnsettledPnl < 0 && oldUnsettledPnl < 0) {
            // when old/new unsettled pnl are both negative:
            // if old > new, it's moving away from 0 (decreasing pnl), bad deb increase
            // if old < new, it's moving closer to 0 (increasing pnl), bad deb decrease
            delta = oldUnsettledPnl - newUnsettledPnl;
        } else if (newUnsettledPnl < 0) {
            // oldUnsettledPnl >= 0 && newUnsettledPnl < 0
            // bad debt increases by -newUnsettledPnl
            delta = newUnsettledPnl.abs().toInt256();
        } else if (oldUnsettledPnl < 0) {
            // oldUnsettledPnl < 0 && newUnsettledPnl >= 0
            // bad debt decreases by -oldUnsettledPnl
            delta = oldUnsettledPnl;
        } else {
            return 0;
        }

        self.badDebt = LibLugiaMath.applyDelta(self.badDebt, delta);
        return delta;
    }
}
