// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibFeeGrowthGlobal } from "./LibFeeGrowthGlobal.sol";
import { BorrowingFeeState, FeeGrowthGlobal } from "./BorrowingFeeStruct.sol";
import { LibLugiaMath } from "../common/LugiaMath.sol";
import { LibError } from "../common/LibError.sol";
import { WAD } from "../common/LibConstant.sol";

/// @dev https://whimsical.com/borrowing-fee-T6auYFHVctGSXNGG1KH4h5
library LibBorrowingFee {
    using SafeCast for *;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;
    using LibLugiaMath for uint256;
    using LibFeeGrowthGlobal for FeeGrowthGlobal;
    using LibBorrowingFee for BorrowingFeeState;

    //
    // INTERNAL
    //

    function addPayerOpenNotional(BorrowingFeeState storage self, int256 payerOpenNotionalDelta) internal {
        self.totalPayerOpenNotional = self.totalPayerOpenNotional.applyDelta(payerOpenNotionalDelta);
    }

    function addReceiverOpenNotional(BorrowingFeeState storage self, int256 receiverOpenNotionalDelta) internal {
        // save the last totalReceiverOpenNotional for utilRatio calculation
        self.lastTotalReceiverOpenNotional = self.totalReceiverOpenNotional;
        self.totalReceiverOpenNotional = self.totalReceiverOpenNotional.applyDelta(receiverOpenNotionalDelta);
    }

    function updateReceiverUtilRatio(
        BorrowingFeeState storage self,
        address receiver,
        uint256 newUtilRatioFactor
    ) internal {
        /// spec: global_ratio = sum(local_ratio * local_open_notional) / total_receiver_open_notional
        /// define factor = local_ratio * local_open_notional; global_ratio = sum(factor) / total_receiver_open_notional
        /// we only know 1 local diff at a time, thus splitting factor to known_factor and other_factors
        /// a. old_global_ratio = (old_factor + sum(other_factors)) / old_total_open_notional
        /// b. new_global_ratio = (new_factor + sum(other_factors)) / new_total_open_notional
        /// every numbers are known except new_global_ratio. sum(other_factors) remains the same between old and new
        /// expansion formula a: sum(other_factors) = old_global_ratio * old_total_open_notional - old_factor
        /// replace sum(other_factors) in formula b:
        /// new_global_ratio = (new_factor + old_global_ratio * old_total_open_notional - old_factor) / new_total_open_notional
        uint256 oldUtilRatioFactor = self.utilRatioFactorMap[receiver];
        uint256 newTotalReceiverOpenNotional = self.totalReceiverOpenNotional;
        uint256 oldUtilRatio = self.utilRatio;
        uint256 newUtilRatio = 0;
        if (newTotalReceiverOpenNotional > 0) {
            // round up the result to prevent from subtraction underflow in next calculation
            newUtilRatio = FixedPointMathLib.divUp(
                oldUtilRatio * self.lastTotalReceiverOpenNotional + newUtilRatioFactor - oldUtilRatioFactor,
                newTotalReceiverOpenNotional
            );
        }

        // it could be more than 100% due to rounding error from divRoundUp
        self.utilRatio = newUtilRatio > WAD ? WAD : newUtilRatio;
        self.utilRatioFactorMap[receiver] = newUtilRatioFactor;
        // sync lastTotalReceiverOpenNotional to totalReceiverOpenNotional after utilRatio is updated
        self.lastTotalReceiverOpenNotional = newTotalReceiverOpenNotional;
    }

    /// @notice
    /// receiverFeeGrowthGlobal: how much fee receiver receives per receiver’s openNotional since beginning.
    /// payerFeeGrowthGlobal: how much fee payer pays per payer’s openNotional since beginning.
    /// @dev
    /// receiverFeeGrowthGlobal = oldFeeGrowthGlobal + delta ( growth means it always accumulate the delta )
    /// receiverFeeGrowthDelta = totalPayerFeeSinceLastUpdated / totalReceiverOpenNotional
    /// payerFeeGrowthGlobal = oldFeeGrowthGlobal + delta ( growth means it always accumulate the delta )
    function settleFeeGrowthGlobal(BorrowingFeeState storage self) internal {
        if (self.feeGrowthGlobal.secondsSinceLastUpdated() == 0) {
            return;
        }
        uint256 payerFeeGrowthDelta = self.getPayerFeeGrowthGlobalDelta();
        uint256 receiverFeeGrowthDelta = self.getReceiverFeeGrowthGlobalDelta();
        self.feeGrowthGlobal.increment(payerFeeGrowthDelta, receiverFeeGrowthDelta);
    }

    /// @dev the formula of "payerFeeGrowthGlobal" contains this state, so it must be settled before this is changed
    function setMaxBorrowingFeeRate(BorrowingFeeState storage self, uint256 newMaxBorrowingFeeRate) internal {
        self.settleFeeGrowthGlobal();
        self.maxBorrowingFeeRate = newMaxBorrowingFeeRate;
    }

    function syncPayerFeeGrowth(BorrowingFeeState storage self, address payer) internal {
        self.payerFeeGrowthMap[payer] = self.feeGrowthGlobal.payer;
    }

    function syncReceiverFeeGrowth(BorrowingFeeState storage self, address receiver) internal {
        self.receiverFeeGrowthMap[receiver] = self.feeGrowthGlobal.receiver;
    }

    //
    // INTERNAL VIEW
    //

    /// @notice calculate how much payer fee growth global should increment since last updated
    /// @dev feeGrowthGlobal = oldFeeGrowthGlobal + delta ( growth means it always accumulate the delta )
    /// delta = maxBorrowingFeeRate * utilRatio * period, multiplied by WAD
    /// (multiply by WAD to minimize rounding error)
    function getPayerFeeGrowthGlobalDelta(BorrowingFeeState storage self) internal view returns (uint256) {
        // incrementalFeeGrowth = borrowingFeeRate * period
        // borrowingFeeRate = utilRatio * maxBorrowingFeeRate
        uint256 utilRatio = self.utilRatio;
        if (utilRatio > WAD) {
            revert LibError.InvalidRatio(utilRatio);
        }

        uint256 secondsSinceLastUpdated = self.feeGrowthGlobal.secondsSinceLastUpdated();
        if (secondsSinceLastUpdated == 0) {
            return 0;
        }

        // normally, utilRatio * maxBorrowingFeeRate should divide by WAD again, but the result we're returning
        // are also multiplied by WAD so we skip this divide
        return self.maxBorrowingFeeRate * secondsSinceLastUpdated * utilRatio;
    }

    /// @notice calculate how much receiver fee growth global should increment since last updated
    /// @dev feeGrowthGlobal = oldFeeGrowthGlobal + delta ( growth means it always accumulate the delta )
    /// delta = totalPayerFeeSinceLastUpdated / totalReceiverOpenNotional, multiplied by WAD
    /// (multiply by WAD to minimize rounding error)
    function getReceiverFeeGrowthGlobalDelta(BorrowingFeeState storage self) internal view returns (uint256) {
        uint256 totalReceiverOpenNotional = self.totalReceiverOpenNotional;
        if (totalReceiverOpenNotional == 0) {
            return 0;
        }

        // borrowingFee per second per totalAbsOpenNotional = max rate * global util ratio
        // total payerFee per second = above * totalAbsOpenNotional
        // total payerFee incremented during this period = above * period
        // total payerFee per total receiver's open notional during this period = above / sum(receiverOpenNotional)
        //
        // normally, utilRatio * totalOpenNotional should divide by WAD again, but the result we're returning
        // are also multiplied by WAD so we skip this divide
        return
            (self.maxBorrowingFeeRate *
                self.utilRatio *
                self.feeGrowthGlobal.secondsSinceLastUpdated() *
                self.totalPayerOpenNotional) / totalReceiverOpenNotional;
    }

    /// @dev caller must ensure it's payer
    function getPendingPayerFee(
        BorrowingFeeState storage self,
        address payer,
        uint256 payerOpenNotionalAbs
    ) internal view returns (int256) {
        // how to calculate feeGrowthDelta:
        // 1. get fee growth global delta since last updated
        // 2. get local fee growth from payerMap (it's the growth global stored when payer updated last time)
        // 3. calculate the difference
        uint256 oldFeeGrowthGlobal = self.feeGrowthGlobal.payer;
        uint256 feeGrowthGlobalDelta = self.getPayerFeeGrowthGlobalDelta();
        uint256 newFeeGrowthGlobal = oldFeeGrowthGlobal + feeGrowthGlobalDelta;
        uint256 feeGrowthLocal = self.payerFeeGrowthMap[payer];
        // payer always pay, fee is always growing, global is always later than local, hence feeGrowthGlobal is always
        // greater than or equals to feeGrowthLocal
        uint256 feeGrowthLocalDelta = newFeeGrowthGlobal - feeGrowthLocal;
        if (feeGrowthLocalDelta == 0) {
            return 0;
        }

        // pendingPayerFee = feeGrowthLocalDelta * payerOpenNotional
        // feeGrowthLocalDelta is multiplied by WAD by definition
        // so besides dividing WAD during multiplying with receiverOpenNotionalAbs, we divide WAD once more
        uint256 pendingPayerFee = feeGrowthLocalDelta.mulWad(payerOpenNotionalAbs) / WAD;
        return pendingPayerFee.toInt256();
    }

    /// @dev caller must ensure it's receiver.
    /// @notice basic version:
    /// totalPayerLongBorrowingFee = longUtilRatio * maxBorrowingFeeRate * deltaTime * totalPayerLongOpenNotionalAbs
    /// receiverLongWeight = receiverStatsLong.openNotional / totalReceiverOpenNotionalLong
    /// receiverLongBorrowingFee = totalLongBorrowingFee * receiverLongWeight
    ///                          = (longUtilRatio * maxBorrowingFeeRate * deltaTime * totalPayerLongOpenNotionalAbs)
    ///                             * (receiverStatsLong.openNotional / totalReceiverOpenNotionalLongAbs)
    /// receiverBorrowingFee = -(receiverLongBorrowingFee + receiverShortBorrowingFee)
    function getPendingReceiverFee(
        BorrowingFeeState storage self,
        address receiver,
        uint256 openNotionalAbs
    ) internal view returns (int256) {
        // calc incremental receiver fee growth for both long and short
        uint256 oldFeeGrowthGlobal = self.feeGrowthGlobal.receiver;
        uint256 feeGrowthGlobalDelta = self.getReceiverFeeGrowthGlobalDelta();
        uint256 newFeeGrowthGlobal = oldFeeGrowthGlobal + feeGrowthGlobalDelta;
        uint256 feeGrowthLocal = self.receiverFeeGrowthMap[receiver];
        uint256 feeGrowthLocalDelta = newFeeGrowthGlobal - feeGrowthLocal;
        if (feeGrowthLocalDelta == 0) {
            return 0;
        }

        // receiver feeGrowth is fee per openNotional
        // receiver always receive borrowing fee, that means receiver fee is negative
        // feeGrowthLocalDelta is multiplied by WAD by definition
        // so besides dividing WAD during multiplying with openNotionalAbs, we divide WAD once more
        uint256 receiverFee = openNotionalAbs.mulWad(feeGrowthLocalDelta) / WAD;
        return -(receiverFee).toInt256();
    }
}
