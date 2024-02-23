// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { LibError } from "../common/LibError.sol";
import { LibPosition } from "../vault/LibPosition.sol";
import { Config } from "../config/Config.sol";
import { IVault } from "../vault/IVault.sol";
import { IBorrowingFee } from "./IBorrowingFee.sol";
import { BorrowingFeeModel } from "./BorrowingFeeModel.sol";

/// @notice There's two roles of trader:
/// - maker: trader who guarantee to provide passive liquidity
/// - taker: trader who take that liquidity.
/// if a certain type of maker qualify some of the criteria (will list after), the system will compensate the
/// liquidity providers by letting other trader paying them borrowing fee. we'll separate them as "payer" and "receiver"
///
/// @notice There are also two roles when it comes to borrowing fee:
/// - receiver: a subset of maker. cannot increase position proactively. cannot censor order in all conditions.
/// - payer: every non-receiver is payer. it could be taker or maker.
///
/// @notice BorrowingFee per seconds = abs(openNotional) * utilRatio * maxBorrowingFeeRate
/// borrowing fee of long and short position are separated. unlike traditional funding rate based on position size,
/// borrowing fee rate is based on open notional.
/// example: given maxBorrowingFeeRate is 10%, there's only 1 receiver with 2 margin. when trader increase 1 long with
/// a receiver when openNotional is 1, if utilRatio = 50%, BorrowingFeeRate = abs(-1) * 0.5 * 0.1 = 0.05 = 5%
contract BorrowingFee is IBorrowingFee, BorrowingFeeModel, AddressResolverUpgradeable {
    using LibAddressResolver for IAddressManager;
    using SafeCast for uint256;
    using SignedMath for int256;

    //
    // STRUCT
    //

    struct SettleBorrowingFeeParams {
        uint256 marketId;
        address trader;
        int256 positionSizeDelta;
        int256 openNotionalDelta;
    }

    //
    // MODIFIER
    //
    modifier onlyVault() {
        if (msg.sender != address(getAddressManager().getVault())) revert LibError.Unauthorized();
        _;
    }

    modifier requireTakerIsPayer(uint256 marketId, address taker) {
        if (_isReceiver(marketId, taker)) {
            revert LibError.InvalidTaker(taker);
        }
        _;
    }

    //
    // INIT
    //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) external initializer {
        __AddressResolver_init(addressManager);
        __BorrowingFeeModel_init();
    }

    //
    // EXTERNAL
    //

    /// @inheritdoc IBorrowingFee
    function setMaxBorrowingFeeRate(
        uint256 marketId,
        uint256 maxLongBorrowingFeeRate,
        uint256 maxShortBorrowingFeeRate
    ) external override {
        if (msg.sender != address(getAddressManager().getConfig())) revert LibError.Unauthorized();
        _setMaxBorrowingFeeRate(marketId, maxLongBorrowingFeeRate, maxShortBorrowingFeeRate);
    }

    /// @dev settle receiver's borrowing fee right before they update margin. won't need to update if it's payer
    /// @inheritdoc IBorrowingFee
    function beforeUpdateMargin(uint256 marketId, address trader) external override onlyVault returns (int256) {
        if (_isReceiver(marketId, trader)) {
            _settleFeeGrowthGlobal(marketId);
            return _settleReceiver(marketId, trader);
        }
        return 0;
    }

    /// @dev must be called if beforeUpdateMargin is called. update util ratio if it's receiver right after they mutated
    /// the margin. won't need to update if it's payer
    /// @inheritdoc IBorrowingFee
    function afterUpdateMargin(uint256 marketId, address trader) external override onlyVault {
        if (_isReceiver(marketId, trader)) {
            _updateUtilRatio(marketId, trader);
        }
    }

    /// @dev if every trader settled at the same time, sum of settledFee between payer/receiver is equaled
    /// @inheritdoc IBorrowingFee
    function beforeSettlePosition(
        uint256 marketId,
        address taker,
        address maker,
        int256 takerPositionSizeDelta,
        int256 takerOpenNotionalDelta
    ) external override onlyVault requireTakerIsPayer(marketId, taker) returns (int256, int256) {
        // posSize delta & openNotional delta must have different sign
        if (takerPositionSizeDelta * takerOpenNotionalDelta > 0) revert LibError.InvalidPosition();

        // if taker trade against itself, settling twice on the same trader will cause issue
        // since we depends on the same previous state. So we just simply skip it since all the global
        // states should be the same after the trade
        if (taker == maker) {
            return (0, 0);
        }

        _settleFeeGrowthGlobal(marketId);

        int256 takerBorrowingFee = _settleBorrowingFee(
            SettleBorrowingFeeParams({
                marketId: marketId,
                trader: taker,
                positionSizeDelta: takerPositionSizeDelta,
                openNotionalDelta: takerOpenNotionalDelta
            })
        );
        int256 makerBorrowingFee = _settleBorrowingFee(
            SettleBorrowingFeeParams({
                marketId: marketId,
                trader: maker,
                positionSizeDelta: -takerPositionSizeDelta,
                openNotionalDelta: -takerOpenNotionalDelta
            })
        );

        return (takerBorrowingFee, makerBorrowingFee);
    }

    /// @dev must be called if beforeSettle is called
    /// @inheritdoc IBorrowingFee
    function afterSettlePosition(uint256 marketId, address maker) external override onlyVault {
        // according to `checkTrader`, only maker could be receiver
        // update local util ratio of that participated receiver
        if (_isReceiver(marketId, maker)) {
            _updateUtilRatio(marketId, maker);
        }
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IBorrowingFee
    function getPendingFee(uint256 marketId, address trader) external view override returns (int256) {
        if (_isReceiver(marketId, trader)) {
            return _getPendingReceiverFee(marketId, trader);
        }
        return _getPendingPayerFee(marketId, trader);
    }

    /// @inheritdoc IBorrowingFee
    function getMaxBorrowingFeeRate(uint256 marketId) external view override returns (uint256, uint256) {
        return _getMaxBorrowingFeeRate(marketId);
    }

    function getTotalReceiverOpenNotional(uint256 marketId) external view returns (uint256, uint256) {
        return _getTotalReceiverOpenNotional(marketId);
    }

    function getTotalPayerOpenNotional(uint256 marketId) external view returns (uint256, uint256) {
        return _getTotalPayerOpenNotional(marketId);
    }

    function getUtilRatio(uint256 marketId) external view returns (uint256, uint256) {
        return _getUtilRatio(marketId);
    }

    //
    // INTERNAL
    //
    function _settleBorrowingFee(SettleBorrowingFeeParams memory params) internal returns (int256) {
        IVault vault = _getVault();
        int256 oldOpenNotional = vault.getOpenNotional(params.marketId, params.trader);
        int256 oldPositionSize = vault.getPositionSize(params.marketId, params.trader);
        bool isUpdatingLong = (oldPositionSize == 0 && params.positionSizeDelta > 0) || oldPositionSize > 0;
        bool isReceiver = _isReceiver(params.marketId, params.trader);

        if (LibPosition.isIncreasing(oldPositionSize, params.positionSizeDelta)) {
            return
                _settleTrader(
                    SettleTraderParams({
                        marketId: params.marketId,
                        trader: params.trader,
                        isUpdatingLong: isUpdatingLong,
                        openNotionalDelta: params.openNotionalDelta.abs().toInt256(),
                        isReceiver: isReceiver
                    })
                );
        }

        // openNotionalDelta and oldOpenNotional have different signs
        // check if it's reduce or close by comparing absolute position size
        // if reduce
        // realizedPnl = oldOpenNotional * closedRatio + openNotionalDelta
        // closedRatio = positionSizeDeltaAbs / positionSizeAbs
        // if close and increase reverse position
        // realizedPnl = oldOpenNotional + openNotionalDelta * closedPositionSize / positionSizeDelta
        uint256 positionSizeDeltaAbs = params.positionSizeDelta.abs();
        uint256 positionSizeAbs = oldPositionSize.abs();
        if (positionSizeAbs >= positionSizeDeltaAbs) {
            // reduce or close position
            // In order to avoid inconsistent rounding error, we must calculate reducedOpenNotional
            // using exactly the same formula as in LibVault.addPosition().
            // When reducing position, since the new account openNotional is calculate as such (refer to the codes in LibVault.addPosition()):
            // newAccountOpenNotional = oldAccountOpenNotional + params.openNotionalDelta - realizedPnl
            //                        = oldAccountOpenNotional + params.openNotionalDelta - (reducedOpenNotional + params.openNotionalDelta)
            //                        = oldAccountOpenNotional + params.openNotionalDelta - ((openNotional * positionSizeDeltaAbs.toInt256()) / positionSizeAbs.toInt256() + params.openNotionalDelta)
            //                        = oldAccountOpenNotional - (openNotional * positionSizeDeltaAbs.toInt256()) / positionSizeAbs.toInt256()
            // Therefore, we want to make sure reducedOpenNotional = (openNotional * positionSizeDeltaAbs.toInt256()) / positionSizeAbs.toInt256()
            int256 reducedOpenNotional = (oldOpenNotional * positionSizeDeltaAbs.toInt256()) /
                positionSizeAbs.toInt256();
            return
                _settleTrader(
                    SettleTraderParams({
                        marketId: params.marketId,
                        trader: params.trader,
                        isUpdatingLong: isUpdatingLong,
                        openNotionalDelta: -reducedOpenNotional.abs().toInt256(),
                        isReceiver: isReceiver
                    })
                );
        }

        // reverse position. close 100% first
        int256 borrowingFee = _settleTrader(
            SettleTraderParams({
                marketId: params.marketId,
                trader: params.trader,
                isUpdatingLong: isUpdatingLong,
                openNotionalDelta: -oldOpenNotional.abs().toInt256(),
                isReceiver: isReceiver
            })
        );

        // In order to avoid inconsistent rounding error, we must calculate remainingOpenNotionalDelta
        // using exactly the same formula as in LibVault.addPosition().
        // When reversing position, since the new account openNotional is calculate as such (refer to the codes in LibVault.addPosition()):
        //        newOpenNotional = position.oldOpenNotional + params.openNotionalDelta - realizedPnl
        //                        = position.oldOpenNotional + params.openNotionalDelta - (position.oldOpenNotional + params.openNotionalDelta * positionSizeAbs / positionSizeDeltaAbs)
        //                        = params.openNotionalDelta - params.openNotionalDelta * positionSizeAbs / positionSizeDeltaAbs
        // Therefore, we want to make sure remainingOpenNotionalDelta = abs(newOpenNotional)
        //                                                            = params.openNotionalDelta - params.openNotionalDelta * positionSizeAbs / positionSizeDeltaAbs
        uint256 remainingOpenNotionalDelta = (params.openNotionalDelta -
            (params.openNotionalDelta * positionSizeAbs.toInt256()) /
            positionSizeDeltaAbs.toInt256()).abs();
        borrowingFee += _settleTrader(
            SettleTraderParams({
                marketId: params.marketId,
                trader: params.trader,
                isUpdatingLong: !isUpdatingLong,
                openNotionalDelta: remainingOpenNotionalDelta.toInt256(),
                isReceiver: isReceiver
            })
        );

        return borrowingFee;
    }

    //
    // INTERNAL VIEW
    //

    function _getVault() internal view returns (IVault) {
        return getAddressManager().getVault();
    }

    /// @inheritdoc BorrowingFeeModel
    function _getOpenNotional(uint256 marketId, address payer) internal view override returns (int256) {
        return _getVault().getOpenNotional(marketId, payer);
    }

    /// @inheritdoc BorrowingFeeModel
    function _getUtilRatioFactor(uint256 marketId, address receiver) internal view override returns (uint256, uint256) {
        return getAddressManager().getMakerReporter().getUtilRatioFactor(marketId, receiver);
    }

    /// @notice every trader must be either borrowing fee payer or receiver
    function _isReceiver(uint256 marketId, address trader) internal view returns (bool) {
        return getAddressManager().getConfig().isWhitelistedMaker(marketId, trader);
    }
}
