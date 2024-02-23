// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IMaker {
    function fillOrder(
        bool isBaseToQuote,
        bool isExactInput,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256 oppositeAmount, bytes memory callbackData);

    function fillOrderCallback(bytes calldata _data) external;

    function getUtilRatio() external view returns (uint256 longUtilRatio, uint256 shortUtilRatio);

    /// @notice caller (which is ClearingHouse) should only pass the trade sent by a valid sender define by maker
    function isValidSender(address sender) external view returns (bool);

    function getAsset() external view returns (address);

    /// @dev Return in asset decimals
    function getTotalAssets(uint256 price) external view returns (int256);
}
