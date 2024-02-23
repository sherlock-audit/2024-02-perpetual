// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

// solhint-disable-next-line max-line-length
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { WAD } from "../common/LibConstant.sol";
import { IPythOracleAdapter } from "../oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { IBorrowingFee } from "../borrowingFee/IBorrowingFee.sol";
import { FundingConfig } from "./FundingConfig.sol";
import { LibError } from "../common/LibError.sol";

contract Config is Ownable2StepUpgradeable, AddressResolverUpgradeable {
    using LibAddressResolver for IAddressManager;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.config
    struct ConfigStorage {
        uint256 maxRelayFee;
        uint256 maxOrderValidDuration;
        uint256 orderDelaySeconds;
        // risk params
        // key: marketId
        mapping(uint256 => uint256) initialMarginRatioMap;
        mapping(uint256 => uint256) maintenanceMarginRatioMap;
        mapping(uint256 => uint256) liquidationFeeRatioMap;
        mapping(uint256 => uint256) liquidationPenaltyRatioMap;
        // key: marketId, value: priceFeedId
        mapping(uint256 => bytes32) marketMap;
        // key: marketId, key: trader
        mapping(uint256 => mapping(address => bool)) whitelistedMakerMap;
        // funding fee related
        // key: marketId, value: fundingConfig
        mapping(uint256 => FundingConfig) fundingConfigMap;
        // key: marketId
        mapping(uint256 => uint256) priceBandRatioMap;
        uint256 depositCap;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.config")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _CONFIG_STORAGE_LOCATION = 0xd52a28ad368ece7953b1a7017c59e62cbf8c1a4757f2dea382bd993edab66400;

    //
    // EVENT
    //

    event OrderDelaySecondsSet(uint256 newOrderDelaySeconds, uint256 oldOrderDelaySeconds);
    event MaxRelayFeeSet(uint256 indexed newMaxRelayFee, uint256 indexed oldMaxRelayFee);
    event MaxOrderValidDurationSet(uint256 newMaxOrderValidDuration, uint256 oldMaxOrderValidDuration);

    event InitialMarginRatioSet(uint256 marketId, uint256 newRatio, uint256 oldRatio);
    event MaintenanceMarginRatioSet(uint256 marketId, uint256 newRatio, uint256 oldRatio);
    event LiquidationFeeRatioSet(uint256 marketId, uint256 newRatio, uint256 oldRatio);
    event LiquidationPenaltyRatioSet(uint256 marketId, uint256 newRatio, uint256 oldRatio);

    event MarketCreated(uint256 marketId, bytes32 priceFeedId);
    event MakerRegistered(uint256 marketId, address maker);
    event FundingConfigSet(
        uint256 marketId,
        uint256 fundingFactor,
        uint256 fundingExponentFactor,
        address basePool,
        uint256 oldFundingFactor,
        uint256 oldFundingExponentFactor,
        address oldBasePool
    );
    event DepositCapSet(uint256 newDepositCap, uint256 oldDepositCap);
    event PriceBandRatioMapSet(uint256 marketId, uint256 newPriceBandRatio, uint256 oldPriceBandRatio);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) public initializer {
        __AddressResolver_init(addressManager);
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
    }

    //
    // EXTERNAL NON VIEW
    //
    function setOrderDelaySeconds(uint256 orderDelaySecondsArg) public onlyOwner {
        uint256 oldOrderDelaySeconds = _getConfigStorage().orderDelaySeconds;
        _getConfigStorage().orderDelaySeconds = orderDelaySecondsArg;

        emit OrderDelaySecondsSet(orderDelaySecondsArg, oldOrderDelaySeconds);
    }

    function setMaxRelayFee(uint256 maxRelayFee) external onlyOwner {
        uint256 oldMaxRelayFee = maxRelayFee;
        _getConfigStorage().maxRelayFee = oldMaxRelayFee;
        emit MaxRelayFeeSet(maxRelayFee, oldMaxRelayFee);
    }

    function setMaxOrderValidDuration(uint256 maxOrderValidDuration) external onlyOwner {
        uint256 oldMaxOrderValidDuration = _getConfigStorage().maxOrderValidDuration;
        _getConfigStorage().maxOrderValidDuration = maxOrderValidDuration;
        emit MaxOrderValidDurationSet(maxOrderValidDuration, oldMaxOrderValidDuration);
    }

    function setInitialMarginRatio(uint256 marketId, uint256 ratio) external onlyOwner {
        _checkValidRatio(ratio);
        if (ratio == 0) revert LibError.ZeroRatio();

        uint256 oldRatio = _getConfigStorage().initialMarginRatioMap[marketId];
        _getConfigStorage().initialMarginRatioMap[marketId] = ratio;
        emit InitialMarginRatioSet(marketId, ratio, oldRatio);
    }

    function setMaintenanceMarginRatio(uint256 marketId, uint256 ratio) external onlyOwner {
        _checkValidRatio(ratio);
        if (ratio == 0) revert LibError.ZeroRatio();

        uint256 oldRatio = _getConfigStorage().maintenanceMarginRatioMap[marketId];
        _getConfigStorage().maintenanceMarginRatioMap[marketId] = ratio;
        emit MaintenanceMarginRatioSet(marketId, ratio, oldRatio);
    }

    function setLiquidationFeeRatio(uint256 marketId, uint256 ratio) external onlyOwner {
        _checkValidRatio(ratio);
        uint256 oldRatio = _getConfigStorage().liquidationFeeRatioMap[marketId];
        _getConfigStorage().liquidationFeeRatioMap[marketId] = ratio;
        emit LiquidationFeeRatioSet(marketId, ratio, oldRatio);
    }

    function setLiquidationPenaltyRatio(uint256 marketId, uint256 ratio) external onlyOwner {
        _checkValidRatio(ratio);
        uint256 oldRatio = _getConfigStorage().liquidationPenaltyRatioMap[marketId];
        _getConfigStorage().liquidationPenaltyRatioMap[marketId] = ratio;
        emit LiquidationPenaltyRatioSet(marketId, ratio, oldRatio);
    }

    function setMaxBorrowingFeeRate(
        uint256 marketId,
        uint256 maxLongBorrowingFeeRate,
        uint256 maxShortBorrowingFeeRate
    ) external onlyOwner {
        getAddressManager().getBorrowingFee().setMaxBorrowingFeeRate(
            marketId,
            maxLongBorrowingFeeRate,
            maxShortBorrowingFeeRate
        );
    }

    function setFundingConfig(
        uint256 marketId,
        uint256 fundingFactor,
        uint256 fundingExponentFactor,
        address basePool
    ) external onlyOwner {
        FundingConfig memory oldFundingConfig = _getConfigStorage().fundingConfigMap[marketId];
        _getConfigStorage().fundingConfigMap[marketId] = FundingConfig({
            fundingFactor: fundingFactor,
            fundingExponentFactor: fundingExponentFactor,
            basePool: basePool
        });

        emit FundingConfigSet(
            marketId,
            fundingFactor,
            fundingExponentFactor,
            basePool,
            oldFundingConfig.fundingFactor,
            oldFundingConfig.fundingExponentFactor,
            oldFundingConfig.basePool
        );
    }

    function setDepositCap(uint256 depositCap) external onlyOwner {
        uint256 oldDepositCap = _getConfigStorage().depositCap;
        _getConfigStorage().depositCap = depositCap;
        emit DepositCapSet(depositCap, oldDepositCap);
    }

    function createMarket(uint256 marketId, bytes32 priceFeedId) external onlyOwner returns (uint256) {
        if (!getAddressManager().getPythOracleAdapter().priceFeedExists(priceFeedId)) {
            revert LibError.IllegalPriceFeed(priceFeedId);
        }

        if (_getConfigStorage().marketMap[marketId] != 0x0) revert LibError.MarketExists(marketId);

        _getConfigStorage().marketMap[marketId] = priceFeedId;

        emit MarketCreated(marketId, priceFeedId);
        return marketId;
    }

    function registerMaker(uint256 marketId, address maker) external onlyOwner {
        if (maker == address(0)) revert LibError.ZeroAddress();

        if (_getConfigStorage().whitelistedMakerMap[marketId][maker]) revert LibError.MakerExists(marketId, maker);

        int256 posSize = getAddressManager().getVault().getPositionSize(marketId, maker);
        if (posSize != 0) revert LibError.MakerHasPosition(marketId, maker, posSize);

        _getConfigStorage().whitelistedMakerMap[marketId][maker] = true;
        emit MakerRegistered(marketId, maker);
    }

    function setPriceBandRatio(uint256 marketId, uint256 priceBandRatio) external onlyOwner {
        _checkValidRatio(priceBandRatio);
        ConfigStorage storage $ = _getConfigStorage();
        uint256 oldPriceBandRatio = $.priceBandRatioMap[marketId];
        $.priceBandRatioMap[marketId] = priceBandRatio;
        emit PriceBandRatioMapSet(marketId, priceBandRatio, oldPriceBandRatio);
    }

    //
    // EXTERNAL VIEW
    //

    /// @notice for maker strategy that requires to mitigate oracle front-running, order must comes from a gateway that
    /// will execute the order in a 2-step process with a delay that's longer than `orderDelaySeconds`
    function getOrderDelaySeconds() external view returns (uint256) {
        return _getConfigStorage().orderDelaySeconds;
    }

    /// @notice for gateway contract that stores the order and execute it later, in order to prevent managing too many
    /// orders, it can stop receiving new orders when the expiration time is greater than `maxOrderValidDuration`
    function getMaxOrderValidDuration() external view returns (uint256) {
        return _getConfigStorage().maxOrderValidDuration;
    }

    /// @notice when someone is trade on behalf of another one, it can charge a relay fee from taker or/and maker that's
    /// less than `maxRelayFee`. denominate in collateral token
    function getMaxRelayFee() external view returns (uint256) {
        return _getConfigStorage().maxRelayFee;
    }

    /// @notice the margin ratio needed to open a position
    function getInitialMarginRatio(uint256 marketId) external view returns (uint256) {
        uint256 mRatio = _getConfigStorage().initialMarginRatioMap[marketId];
        if (mRatio == 0) {
            return 1 ether; // 100%
        }
        return mRatio;
    }

    /// @dev the margin ratio required to prevent liquidation
    function getMaintenanceMarginRatio(uint256 marketId) external view returns (uint256) {
        uint256 mRatio = _getConfigStorage().maintenanceMarginRatioMap[marketId];
        if (mRatio == 0) {
            return 1 ether; // 100%
        }
        return mRatio;
    }

    /// @dev how much percentage of the liquidation penalty liquidator can receive
    function getLiquidationFeeRatio(uint256 marketId) external view returns (uint256) {
        uint256 feeRatio = _getConfigStorage().liquidationFeeRatioMap[marketId];
        return feeRatio;
    }

    /// @dev how much notional value of the liquidated position will be charged as penalty
    function getLiquidationPenaltyRatio(uint256 marketId) external view returns (uint256) {
        uint256 penaltyRatio = _getConfigStorage().liquidationPenaltyRatioMap[marketId];
        return penaltyRatio;
    }

    /// @dev the borrowing fee rate when all borrowing fee receiver's utilization ratio is 100%
    function getMaxBorrowingFeeRate(uint256 marketId) external view returns (uint256, uint256) {
        return IBorrowingFee(getAddressManager().getBorrowingFee()).getMaxBorrowingFeeRate(marketId);
    }

    /// @dev pyth's price feed id of that market
    function getPriceFeedId(uint256 marketId) external view returns (bytes32) {
        return _getConfigStorage().marketMap[marketId];
    }

    function getFundingConfig(uint256 marketId) external view returns (FundingConfig memory) {
        return _getConfigStorage().fundingConfigMap[marketId];
    }

    /// @dev maker who can trade with callback and receiving borrowing fee
    function isWhitelistedMaker(uint256 marketId, address trader) external view returns (bool) {
        return _getConfigStorage().whitelistedMakerMap[marketId][trader];
    }

    /// @dev the maximum amount of deposit allowed
    function getDepositCap() external view returns (uint256) {
        return _getConfigStorage().depositCap;
    }

    function getPriceBandRatio(uint256 marketId) external view returns (uint256) {
        return _getConfigStorage().priceBandRatioMap[marketId];
    }

    //
    // INTERNAL
    //
    function _checkValidRatio(uint256 ratio) internal pure {
        if (ratio > WAD) {
            revert LibError.InvalidRatio(ratio);
        }
    }

    //
    // PRIVATE
    //

    function _getConfigStorage() private pure returns (ConfigStorage storage $) {
        assembly {
            $.slot := _CONFIG_STORAGE_LOCATION
        }
    }
}
