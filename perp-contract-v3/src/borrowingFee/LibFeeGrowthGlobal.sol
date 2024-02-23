// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { FeeGrowthGlobal } from "./BorrowingFeeStruct.sol";

library LibFeeGrowthGlobal {
    function increment(
        FeeGrowthGlobal storage self,
        uint256 payerFeeGrowthDelta,
        uint256 receiverFeeGrowthDelta
    ) internal {
        self.payer += payerFeeGrowthDelta;
        self.receiver += receiverFeeGrowthDelta;
        self.lastUpdated = block.timestamp;
    }

    function secondsSinceLastUpdated(FeeGrowthGlobal storage self) internal view returns (uint256) {
        return block.timestamp - self.lastUpdated;
    }
}
