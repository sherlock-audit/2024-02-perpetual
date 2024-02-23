// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IBorrowingFeeEvent {
    event UtilRatioChanged(
        uint256 indexed marketId,
        uint256 longUtilRatio,
        uint256 shortUtilRatio,
        uint256 oldLongUtilRatio,
        uint256 oldShortUtilRatio
    );

    /// @notice positive borrowingFee means paying, and taker always pays borrowingFee
    /// @notice negative borrowingFee means receiving, and maker always receives borrowingFee
    event BorrowingFeeSettled(uint256 indexed marketId, address indexed trader, int256 borrowingFee);

    event MaxBorrowingFeeRateSet(
        uint256 indexed marketId,
        uint256 longMaxBorowingFeeRate,
        uint256 shortMaxBorowingFeeRate,
        uint256 oldLongMaxBorowingFeeRate,
        uint256 oldShortMaxBorowingFeeRate
    );
}
