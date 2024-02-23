// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import { PositionChangedReason } from "./PositionChangedReason.sol";
import { IMarginProfile } from "./IMarginProfile.sol";

interface IVault is IMarginProfile {
    struct SettlePositionParams {
        uint256 marketId;
        address taker;
        address maker;
        int256 takerPositionSize;
        int256 takerOpenNotional;
        PositionChangedReason reason;
    }

    /// @param amountXCD in collateral's decimals
    function deposit(address trader, uint256 amountXCD) external;

    /// @param amountXCD in collateral's decimals
    function withdraw(uint256 amountXCD) external;

    /// @notice amountXCD is denominated in collateral token's decimals
    function transferFundToMargin(uint256 marketId, uint256 amountXCD) external;

    /// @notice amountXCD is denominated in collateral token's decimals
    function transferFundToMargin(uint256 marketId, address trader, uint256 amountXCD) external;

    /// @notice amountXCD is denominated in collateral token's decimals
    function transferMarginToFund(uint256 marketId, uint256 amountXCD) external;

    /// @notice amountXCD is denominated in collateral token's decimals
    function transferMarginToFund(uint256 marketId, address trader, uint256 amountXCD) external;

    function settlePosition(SettlePositionParams calldata params) external;

    function transferFund(address from, address to, uint256 amountXCD) external;

    /// @notice transfer margin between "from" and "to" account
    function transferMargin(uint256 marketId, address from, address to, uint256 amount) external;

    //
    // VIEW
    //

    function getUnsettledPnl(uint256 marketId, address trader) external view returns (int256 unsettledPnl);

    function getFund(address trader) external view returns (uint256 fund);

    function getSettledMargin(uint256 marketId, address trader) external view returns (int256 marginWithoutPending);

    function getCollateralToken() external view returns (address collateralToken);
}
