// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IMakerReporter {
    function getUtilRatioFactor(uint256 marketId, address receiver) external view returns (uint256, uint256);
}
