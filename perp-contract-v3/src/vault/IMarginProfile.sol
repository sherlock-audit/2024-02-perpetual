// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

enum MarginRequirementType {
    INITIAL,
    MAINTENANCE
}

interface IMarginProfile {
    /// @notice margin ratio = account value / open notional
    function getMarginRatio(uint256 marketId, address trader, uint256 price) external view returns (int256);

    /// @notice free collateral (for withdrawal) = min(free margin, account value) - initial margin requirement
    function getFreeCollateral(uint256 marketId, address trader, uint256 price) external view returns (uint256);

    /// @notice free collateral (for trade) = min(margin, account value) - initial or maintenance margin requirement
    /// INITIAL is for increasing position, MAINTENANCE is for reducing position
    function getFreeCollateralForTrade(
        uint256 marketId,
        address trader,
        uint256 price,
        MarginRequirementType marginRequirementType
    ) external view returns (int256);

    /// @notice margin requirement = open notional * required margin ratio (initial or maintenance)
    function getMarginRequirement(
        uint256 marketId,
        address trader,
        MarginRequirementType marginRequirementType
    ) external view returns (uint256);

    /// @notice unrealized pnl = position value + open notional
    function getUnrealizedPnl(uint256 marketId, address trader, uint256 price) external view returns (int256);

    /// @notice account value = margin (note it should include unsettled pnl and borrowing fee) + unrealized pnl
    function getAccountValue(uint256 marketId, address trader, uint256 price) external view returns (int256);

    /// @notice the margin trader can use for trading. when positive, it's always greater than or equal to "free margin"
    function getMargin(uint256 marketId, address trader) external view returns (int256);

    /// @notice the margin trader can access in any cases. it may be less than margin when pnl pool doesn't has enough
    /// liquidity for unsettled profit
    function getFreeMargin(uint256 marketId, address trader) external view returns (uint256);

    function getOpenNotional(uint256 marketId, address trader) external view returns (int256);

    function getPositionSize(uint256 marketId, address trader) external view returns (int256);
}
