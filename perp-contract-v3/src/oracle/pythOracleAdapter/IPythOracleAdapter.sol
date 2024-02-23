// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IPythOracleAdapter {
    event OracleDataUsed(bytes32 priceFeedId, uint price, uint decimals, uint expirationTime);
    event OracleFeeDeposited(address from, uint256 amount);
    event OracleFeeWithdrawn(address to, uint256 amount);
    event MaxPriceAgeSet(uint256 maxPriceAge, uint256 oldMaxPriceAge);

    function priceFeedExists(bytes32 priceFeedId) external view returns (bool);

    function updatePrice(bytes32 priceFeedId, bytes calldata signedData) external;

    /// @dev Returns the price in INTERNAL_DECIMALS.
    function getPrice(bytes32 priceFeedId) external view returns (uint256 price, uint256 publishTimestamp);
}
