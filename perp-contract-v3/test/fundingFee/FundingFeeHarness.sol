// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../src/fundingFee/FundingFee.sol";

contract FundingFeeHarness is FundingFee {
    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function exposed_getFundingFeeStorage() private pure returns (FundingFee.FundingFeeStorage storage $) {
        assembly {
            $.slot := _FUNDING_FEE_STORAGE_LOCATION
        }
    }

    function exposed_FUNDING_FEE_STORAGE_LOCATION() external view returns (bytes32) {
        return _FUNDING_FEE_STORAGE_LOCATION;
    }

    function exposed_updateFundingGrowthIndex(uint256 marketId) external {
        _updateFundingGrowthIndex(marketId);
    }

    function exposed_settleFundingFee(uint256 marketId, address trader) external returns (int256) {
        return _settleFundingFee(marketId, trader);
    }

    function exposed_fundingGrowthLongIndexMap(uint256 marketId) external view returns (int256) {
        return exposed_getFundingFeeStorage().fundingGrowthLongIndexMap[marketId];
    }

    function exposed_lastUpdatedTimestampMap(uint256 marketId) external view returns (uint256) {
        return exposed_getFundingFeeStorage().lastUpdatedTimestampMap[marketId];
    }

    function exposed_lastFundingGrowthLongIndexMap(uint256 marketId, address trader) external view returns (int256) {
        return exposed_getFundingFeeStorage().lastFundingGrowthLongIndexMap[marketId][trader];
    }

    function exposed_calcFundingFee(int256 openNotional, int256 deltaGrowthIndex) external pure returns (int256) {
        return _calcFundingFee(openNotional, deltaGrowthIndex);
    }

    function setFundingGrowthLongIndex(uint256 marketId, int256 value) external {
        exposed_getFundingFeeStorage().fundingGrowthLongIndexMap[marketId] = value;
    }

    function setLastUpdatedTimestamp(uint256 marketId, uint256 value) external {
        exposed_getFundingFeeStorage().lastUpdatedTimestampMap[marketId] = value;
    }
}
