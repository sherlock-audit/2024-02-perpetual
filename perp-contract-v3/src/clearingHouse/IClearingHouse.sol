// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

interface IClearingHouse {
    /// @param makerData Encoded calls are custom data defined by maker
    struct OpenPositionParams {
        uint256 marketId;
        address maker;
        bool isBaseToQuote;
        bool isExactInput;
        uint256 amount;
        uint256 oppositeAmountBound;
        uint256 deadline;
        bytes makerData;
    }

    /// @notice same as OpenPositionParams with extra params
    struct OpenPositionForParams {
        uint256 marketId;
        address maker;
        bool isBaseToQuote;
        bool isExactInput;
        uint256 amount;
        uint256 oppositeAmountBound;
        uint256 deadline;
        bytes makerData;
        // the following are extra params
        address taker;
        uint256 takerRelayFee;
        uint256 makerRelayFee;
    }

    /// @param makerData Encoded calls are custom data defined by maker
    struct ClosePositionParams {
        uint256 marketId;
        address maker;
        uint256 oppositeAmountBound;
        uint256 deadline;
        bytes makerData;
    }

    /// @notice same as OpenPositionParams with extra params
    struct ClosePositionForParams {
        uint256 marketId;
        address maker;
        uint256 oppositeAmountBound;
        uint256 deadline;
        bytes makerData;
        // extra params
        address taker;
        uint256 takerRelayFee;
        uint256 makerRelayFee;
    }

    struct LiquidatePositionParams {
        uint256 marketId;
        address trader;
        // size liquidator request for liquidating
        uint256 positionSize;
    }

    struct MakerOrder {
        uint256 amount;
    }

    event Liquidated(
        uint256 indexed marketId,
        address indexed liquidator,
        address indexed trader,
        int256 positionSizeDelta,
        int256 positionNotionalDelta,
        uint256 price,
        uint256 penalty,
        uint256 liquidationFeeToLiquidator,
        uint256 liquidationFeeToProtocol
    );

    function openPosition(OpenPositionParams calldata params) external returns (int256 base, int256 quote);

    function openPositionFor(OpenPositionForParams calldata params) external returns (int256 base, int256 quote);

    function quoteOpenPosition(OpenPositionParams calldata params) external returns (int256 base, int256 quote);

    function closePosition(ClosePositionParams calldata params) external returns (int256 base, int256 quote);

    function closePositionFor(ClosePositionForParams calldata params) external returns (int256 base, int256 quote);

    function liquidate(
        LiquidatePositionParams calldata params
    ) external returns (int256 liquidatedAccountBaseDelta, int256 liquidatedAccountQuoteDelta);

    function decodeMakerOrder(bytes calldata encoded) external pure returns (MakerOrder memory);

    function isLiquidatable(uint256 marketId, address trader, uint256 price) external view returns (bool);

    function getLiquidatablePositionSize(
        uint256 marketId,
        address trader,
        uint256 price
    ) external view returns (int256 positionSize);
}
