// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IBorrowingFee {
    /// @notice if trader is receiver, emit BorrowingFeeSettled
    function beforeUpdateMargin(uint256 marketId, address trader) external returns (int256 settledBorrowingFee);

    function afterUpdateMargin(uint256 marketId, address trader) external;

    /// @return payerFee how much fee payer pays. always positive
    /// @return receiverFee how much fee receiver receives. always negative (negative fee = revenue)
    function beforeSettlePosition(
        uint256 marketId,
        address taker,
        address maker,
        int256 takerPositionSizeDelta,
        int256 takerOpenNotionalDelta
    ) external returns (int256 payerFee, int256 receiverFee);

    function afterSettlePosition(uint256 marketId, address maker) external;

    /// @notice emit MaxBorrowingFeeRateSet
    function setMaxBorrowingFeeRate(
        uint256 marketId,
        uint256 maxLongBorrowingFeeRate,
        uint256 maxShortBorrowingFeeRate
    ) external;

    function getMaxBorrowingFeeRate(uint256 marketId) external view returns (uint256, uint256);

    /// @notice how much pending fee in trader's perspective.
    /// @return pendingFee margin will decrease if fee is positive, increase if fee is negative.
    function getPendingFee(uint256 marketId, address trader) external view returns (int256 pendingFee);
}
