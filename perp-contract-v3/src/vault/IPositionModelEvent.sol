// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { PositionChangedReason } from "./PositionChangedReason.sol";

interface IPositionModelEvent {
    event PositionChanged(
        uint256 indexed marketId,
        address indexed trader,
        address maker,
        int256 positionSizeDelta,
        int256 openNotionalDelta,
        int256 realizedPnl,
        PositionChangedReason reason
    );

    event PnlSettled(
        uint256 indexed marketId,
        address indexed trader,
        int256 realizedPnl, // PnL realized during the settlement. This and the trader's existing unsettled PnL
        // combined is the total amount we're trying to settle.
        int256 settledPnl, // Amount of PnL settled and added to the trader's margin.
        uint256 margin, // Trader's margin after settlement.
        int256 unsettledPnl, // Trader's unsettled PnL after settlement.
        uint256 pnlPoolBalance // PnL Pool balance after settlement.
    );

    event MarginChanged(uint256 indexed marketId, address indexed trader, int256 marginDelta);
    event BadDebtChanged(uint256 indexed marketId, int256 badDebtDelta);
}
