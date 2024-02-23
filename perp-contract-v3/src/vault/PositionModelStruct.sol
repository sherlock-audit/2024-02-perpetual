// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

struct PositionModelState {
    uint256 pnlPoolBalance;
    uint256 badDebt;
    // key: trader address => position
    mapping(address => Position) positionMap;
}

/// @notice all in INTERNAL_DECIMALS
struct Position {
    uint256 margin;
    int256 positionSize;
    int256 openNotional;
    int256 unsettledPnl;
}
