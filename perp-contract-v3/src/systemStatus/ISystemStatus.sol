// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

interface ISystemStatus {
    event SystemSuspended();
    event SystemResumed();
    event MarketSuspended(uint256 marketId);
    event MarketResumed(uint256 marketId);

    function systemSuspended() external view returns (bool);

    function marketSuspendedMap(uint256 marketId) external view returns (bool);

    function requireSystemActive() external view;

    function requireMarketActive(uint256 marketId) external view;
}
