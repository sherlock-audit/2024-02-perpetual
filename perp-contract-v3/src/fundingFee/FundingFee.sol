// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { LibError } from "../common/LibError.sol";
import { WAD } from "../common/LibConstant.sol";
import { FundingConfig } from "../config/FundingConfig.sol";
import { OracleMaker } from "../maker/OracleMaker.sol";
import { IVault } from "../vault/IVault.sol";
import { Config } from "../config/Config.sol";
import { IFundingFee } from "./IFundingFee.sol";

contract FundingFee is AddressResolverUpgradeable, IFundingFee {
    using SafeCast for *;
    using FixedPointMathLib for int256;
    using LibAddressResolver for IAddressManager;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.fundingFee
    struct FundingFeeStorage {
        // key: marketId, value: fundingGrowthLongIndex
        mapping(uint256 => int256) fundingGrowthLongIndexMap;
        // key: marketId, value: lastUpdatedTimestamp
        mapping(uint256 => uint256) lastUpdatedTimestampMap;
        mapping(uint256 => mapping(address => int256)) lastFundingGrowthLongIndexMap;
    }

    event FundingFeeSettled(uint256 marketId, address trader, int256 fundingFee);

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.fundingFee")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _FUNDING_FEE_STORAGE_LOCATION = 0x67af2bbd5c68531270a033011670248db9cc70016659ba644098886bbb018000;

    //
    // MODIFIER
    //
    modifier onlyVault() {
        if (msg.sender != address(_getVault())) revert LibError.Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) external initializer {
        __AddressResolver_init(addressManager);
    }

    //
    // EXTERNAL
    //

    /// @inheritdoc IFundingFee
    function beforeUpdateMargin(uint256 marketId, address trader) external onlyVault returns (int256) {
        _updateFundingGrowthIndex(marketId);
        int256 fundingFee = _settleFundingFee(marketId, trader);
        return fundingFee;
    }

    /// @inheritdoc IFundingFee
    function beforeSettlePosition(
        uint256 marketId,
        address taker,
        address maker
    ) external onlyVault returns (int256, int256) {
        _updateFundingGrowthIndex(marketId);
        int256 takerFundingFee = _settleFundingFee(marketId, taker);
        int256 makerFundingFee = _settleFundingFee(marketId, maker);
        return (takerFundingFee, makerFundingFee);
    }

    //
    // PUBLIC VIEW
    //

    /// @inheritdoc IFundingFee
    function getPendingFee(uint256 marketId, address trader) public view returns (int256) {
        int256 fundingRate = getCurrentFundingRate(marketId);
        int256 fundingGrowthLongIndex = _getFundingFeeStorage().fundingGrowthLongIndexMap[marketId] +
            (fundingRate * int256(block.timestamp - _getFundingFeeStorage().lastUpdatedTimestampMap[marketId]));
        int256 openNotional = _getVault().getOpenNotional(marketId, trader);
        int256 fundingFee = 0;
        if (openNotional != 0) {
            fundingFee = _calcFundingFee(
                openNotional,
                fundingGrowthLongIndex - _getFundingFeeStorage().lastFundingGrowthLongIndexMap[marketId][trader]
            );
        }
        return fundingFee;
    }

    function getCurrentFundingRate(uint256 marketId) public view returns (int256) {
        Config config = getAddressManager().getConfig();
        FundingConfig memory fundingConfig = config.getFundingConfig(marketId);

        if (fundingConfig.basePool == address(0)) {
            return 0;
        }

        int256 openNotional = _getVault().getOpenNotional(marketId, fundingConfig.basePool);
        if (openNotional == 0) {
            return 0;
        }

        uint256 openNotionalAbs = openNotional.abs();
        bool isBasePoolLong = openNotional < 0;

        // we can only use margin without pendingMargin as totalDepositedAmount
        // since pendingMargin includes pending borrowingFee and fundingFee,
        // it will be infinite loop dependency
        uint256 totalDepositedAmount = uint256(_getVault().getSettledMargin(marketId, fundingConfig.basePool));
        uint256 maxCapacity = FixedPointMathLib.divWad(
            totalDepositedAmount,
            uint256(OracleMaker(fundingConfig.basePool).minMarginRatio())
        );

        // maxCapacity = basePool.totalDepositedAmount / basePool.minMarginRatio
        // imbalanceRatio = basePool.openNotional^fundingExponentFactor / maxCapacity
        // fundingRate = fundingFactor * imbalanceRatio
        // funding = trader.openNotional * fundingRate * deltaTimeInSeconds
        uint256 fundingRateAbs = FixedPointMathLib.fullMulDiv(
            fundingConfig.fundingFactor,
            FixedPointMathLib
                .powWad(openNotionalAbs.toInt256(), fundingConfig.fundingExponentFactor.toInt256())
                .toUint256(),
            maxCapacity
        );

        // positive -> basePool is long -> receive funding for long position, pay funding for short position
        // negative -> basePool is short -> receive funding for short position, pay funding for long position,
        int256 fundingRate = isBasePoolLong ? int256(fundingRateAbs) : -int256(fundingRateAbs);
        return fundingRate;
    }

    //
    // INTERNAL
    //

    function _updateFundingGrowthIndex(uint256 marketId) internal {
        int256 fundingRate = getCurrentFundingRate(marketId);
        // index increase -> receive funding
        // index reduce   -> pay funding
        _getFundingFeeStorage().fundingGrowthLongIndexMap[marketId] +=
            fundingRate *
            int256(block.timestamp - _getFundingFeeStorage().lastUpdatedTimestampMap[marketId]);
        _getFundingFeeStorage().lastUpdatedTimestampMap[marketId] = block.timestamp;
    }

    /// @dev caller must ensure _updateFundingGrowthIndex() is called before calling this function
    function _settleFundingFee(uint256 marketId, address trader) internal returns (int256) {
        int256 fundingGrowthLongIndex = _getFundingFeeStorage().fundingGrowthLongIndexMap[marketId];
        int256 openNotional = _getVault().getOpenNotional(marketId, trader);
        int256 fundingFee = 0;
        if (openNotional != 0) {
            fundingFee = _calcFundingFee(
                openNotional,
                fundingGrowthLongIndex - _getFundingFeeStorage().lastFundingGrowthLongIndexMap[marketId][trader]
            );
        }
        _getFundingFeeStorage().lastFundingGrowthLongIndexMap[marketId][trader] = _getFundingFeeStorage()
            .fundingGrowthLongIndexMap[marketId];

        emit FundingFeeSettled(marketId, trader, fundingFee);
        return fundingFee;
    }

    //
    // INTERNAL VIEW
    //

    /// @notice positive -> pay funding fee -> fundingFee should round up
    /// negative -> receive funding fee -> -fundingFee should round down
    function _calcFundingFee(int256 openNotional, int256 deltaGrowthIndex) internal pure returns (int256) {
        if (openNotional * deltaGrowthIndex > 0) {
            return int256(FixedPointMathLib.fullMulDivUp(openNotional.abs(), deltaGrowthIndex.abs(), WAD));
        } else {
            return (openNotional * deltaGrowthIndex) / WAD.toInt256();
        }
    }

    function _getVault() internal view returns (IVault) {
        return getAddressManager().getVault();
    }

    function _getFundingFeeStorage() private pure returns (FundingFeeStorage storage $) {
        assembly {
            $.slot := _FUNDING_FEE_STORAGE_LOCATION
        }
    }
}
