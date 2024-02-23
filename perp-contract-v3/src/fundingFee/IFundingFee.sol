// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IFundingFee {
    function beforeUpdateMargin(uint256 marketId, address trader) external returns (int256 settledBorrowingFee);

    function beforeSettlePosition(
        uint256 marketId,
        address taker,
        address maker
    ) external returns (int256 takerFee, int256 makerFee);

    /// @notice how much pending fee in trader's perspective.
    /// @return pendingFee margin will decrease if fee is positive, increase if fee is negative.
    function getPendingFee(uint256 marketId, address trader) external view returns (int256 pendingFee);
}
