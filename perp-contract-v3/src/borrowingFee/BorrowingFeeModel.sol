// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBorrowingFee } from "./LibBorrowingFee.sol";
import { IBorrowingFeeEvent } from "./IBorrowingFeeEvent.sol";
import { BorrowingFeeState } from "./BorrowingFeeStruct.sol";

/// @dev the only entry point to get & set BorrowingFeeState
/// @dev the only place to emit IBorrowingFeeEvent
abstract contract BorrowingFeeModel is Initializable, IBorrowingFeeEvent {
    using LibBorrowingFee for BorrowingFeeState;
    using FixedPointMathLib for int256;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.borrowingFeeModel
    struct BorrowingFeeModelStorage {
        // "long" and "short" are from the perspective of the payer
        // key by marketId
        mapping(uint256 => BorrowingFeeState) longStateMap;
        mapping(uint256 => BorrowingFeeState) shortStateMap;
    }

    struct SettleTraderParams {
        uint256 marketId;
        address trader;
        bool isUpdatingLong;
        int256 openNotionalDelta;
        bool isReceiver;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.borrowingFeeModel")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _BORROWING_FEE_MODEL_STORAGE_LOCATION =
        0x7f84e967717eb3e96357284749df629501c189b79d16f6d9386ed539834b2500;

    //
    // INIT
    //
    function __BorrowingFeeModel_init() internal onlyInitializing {}

    //
    // INTERNAL
    //
    function _settleFeeGrowthGlobal(uint256 marketId) internal {
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        $.longStateMap[marketId].settleFeeGrowthGlobal();
        $.shortStateMap[marketId].settleFeeGrowthGlobal();
    }

    function _settleTrader(SettleTraderParams memory params) internal returns (int256) {
        // 1. settle trader's fee and sync global to local
        // 2. update global states that depends on this operation
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();

        int256 borrowingFee;
        if (params.isReceiver) {
            borrowingFee = _settleReceiverBorrowingFee(params.marketId, params.trader);
            // receiver has long -> counter party of payer's short -> short state
            BorrowingFeeState storage updatingState = params.isUpdatingLong
                ? $.shortStateMap[params.marketId]
                : $.longStateMap[params.marketId];
            updatingState.addReceiverOpenNotional(params.openNotionalDelta);
        } else {
            borrowingFee = _settlePayerBorrowingFee(params.marketId, params.trader);
            BorrowingFeeState storage updatingState = params.isUpdatingLong
                ? $.longStateMap[params.marketId]
                : $.shortStateMap[params.marketId];
            updatingState.addPayerOpenNotional(params.openNotionalDelta);
        }

        _emitBorrowingFeeSettled(params.marketId, params.trader, borrowingFee);
        return borrowingFee;
    }

    function _settleReceiver(uint256 marketId, address receiver) internal returns (int256) {
        int256 receiverBorrowingFee = _settleReceiverBorrowingFee(marketId, receiver);
        _emitBorrowingFeeSettled(marketId, receiver, receiverBorrowingFee);
        return receiverBorrowingFee;
    }

    function _updateUtilRatio(uint256 marketId, address receiver) internal {
        (uint256 longUtilRatioFactor, uint256 shortUtilRatioFactor) = _getUtilRatioFactor(marketId, receiver);
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        BorrowingFeeState storage longState = $.longStateMap[marketId];
        BorrowingFeeState storage shortState = $.shortStateMap[marketId];
        uint256 oldLongUtilRatio = longState.utilRatio;
        uint256 oldShortUtilRatio = shortState.utilRatio;
        $.longStateMap[marketId].updateReceiverUtilRatio(receiver, longUtilRatioFactor);
        $.shortStateMap[marketId].updateReceiverUtilRatio(receiver, shortUtilRatioFactor);

        _emitUtilRatioChanged(marketId, longState.utilRatio, shortState.utilRatio, oldLongUtilRatio, oldShortUtilRatio);
    }

    function _setMaxBorrowingFeeRate(
        uint256 marketId,
        uint256 newMaxLongBorrowingFeeRate,
        uint256 newMaxShortBorrowingFeeRate
    ) internal {
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        uint256 oldMaxLongBorrowingFeeRate = $.longStateMap[marketId].maxBorrowingFeeRate;
        uint256 oldMaxShortBorrowingFeeRate = $.shortStateMap[marketId].maxBorrowingFeeRate;
        $.longStateMap[marketId].setMaxBorrowingFeeRate(newMaxLongBorrowingFeeRate);
        $.shortStateMap[marketId].setMaxBorrowingFeeRate(newMaxShortBorrowingFeeRate);
        emit MaxBorrowingFeeRateSet(
            marketId,
            newMaxLongBorrowingFeeRate,
            newMaxShortBorrowingFeeRate,
            oldMaxLongBorrowingFeeRate,
            oldMaxShortBorrowingFeeRate
        );
    }

    //
    // INTERNAL VIEW
    //

    function _getPendingPayerFee(uint256 marketId, address payer) internal view returns (int256) {
        int256 openNotional = _getOpenNotional(marketId, payer);
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        int256 payerBorrowingFee;
        if (openNotional > 0) {
            payerBorrowingFee = $.shortStateMap[marketId].getPendingPayerFee(payer, openNotional.abs());
        } else if (openNotional < 0) {
            payerBorrowingFee = $.longStateMap[marketId].getPendingPayerFee(payer, openNotional.abs());
        }
        return payerBorrowingFee;
    }

    function _getPendingReceiverFee(uint256 marketId, address receiver) internal view returns (int256) {
        int256 openNotional = _getOpenNotional(marketId, receiver);
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        int256 receiverBorrowingFee;
        if (openNotional > 0) {
            // receiver holds short -> counter party of payer's long -> long's borrowing fee
            receiverBorrowingFee = $.longStateMap[marketId].getPendingReceiverFee(receiver, openNotional.abs());
        } else if (openNotional < 0) {
            // receiver holds long -> counter party of payer's short -> short's borrowing fee
            receiverBorrowingFee = $.shortStateMap[marketId].getPendingReceiverFee(receiver, openNotional.abs());
        }
        return receiverBorrowingFee;
    }

    function _getUtilRatio(uint256 marketId) internal view returns (uint256, uint256) {
        return (
            _getBorrowingFeeModelStorage().longStateMap[marketId].utilRatio,
            _getBorrowingFeeModelStorage().shortStateMap[marketId].utilRatio
        );
    }

    function _getTotalReceiverOpenNotional(uint256 marketId) internal view returns (uint256, uint256) {
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        return (
            $.longStateMap[marketId].totalReceiverOpenNotional,
            $.shortStateMap[marketId].totalReceiverOpenNotional
        );
    }

    function _getTotalPayerOpenNotional(uint256 marketId) internal view returns (uint256, uint256) {
        return (
            _getBorrowingFeeModelStorage().longStateMap[marketId].totalPayerOpenNotional,
            _getBorrowingFeeModelStorage().shortStateMap[marketId].totalPayerOpenNotional
        );
    }

    function _getPayerFeeGrowth(uint256 marketId, address payer) internal view returns (uint256, uint256) {
        return (
            _getBorrowingFeeModelStorage().longStateMap[marketId].payerFeeGrowthMap[payer],
            _getBorrowingFeeModelStorage().shortStateMap[marketId].payerFeeGrowthMap[payer]
        );
    }

    function _getPayerFeeGrowthGlobal(uint256 marketId) internal view returns (uint256, uint256) {
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        return ($.longStateMap[marketId].feeGrowthGlobal.payer, $.shortStateMap[marketId].feeGrowthGlobal.payer);
    }

    function _getReceiverFeeGrowth(uint256 marketId, address receiver) internal view returns (uint256, uint256) {
        return (
            _getBorrowingFeeModelStorage().longStateMap[marketId].receiverFeeGrowthMap[receiver],
            _getBorrowingFeeModelStorage().shortStateMap[marketId].receiverFeeGrowthMap[receiver]
        );
    }

    function _getReceiverFeeGrowthGlobal(uint256 marketId) internal view returns (uint256, uint256) {
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        return ($.longStateMap[marketId].feeGrowthGlobal.receiver, $.shortStateMap[marketId].feeGrowthGlobal.receiver);
    }

    function _getMaxBorrowingFeeRate(uint256 marketId) internal view returns (uint256, uint256) {
        return (
            _getBorrowingFeeModelStorage().longStateMap[marketId].maxBorrowingFeeRate,
            _getBorrowingFeeModelStorage().shortStateMap[marketId].maxBorrowingFeeRate
        );
    }

    //
    // INTERNAL VIEW VIRTUAL
    //
    function _getUtilRatioFactor(uint256 marketId, address receiver) internal view virtual returns (uint256, uint256);

    function _getOpenNotional(uint256 marketId, address payer) internal view virtual returns (int256);

    //
    // PRIVATE
    //

    function _settlePayerBorrowingFee(uint256 marketId, address payer) private returns (int256) {
        int256 payerBorrowingFee = _getPendingPayerFee(marketId, payer);
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        $.longStateMap[marketId].syncPayerFeeGrowth(payer);
        $.shortStateMap[marketId].syncPayerFeeGrowth(payer);
        return payerBorrowingFee;
    }

    function _settleReceiverBorrowingFee(uint256 marketId, address receiver) private returns (int256) {
        int256 receiverBorrowingFee = _getPendingReceiverFee(marketId, receiver);
        BorrowingFeeModelStorage storage $ = _getBorrowingFeeModelStorage();
        $.longStateMap[marketId].syncReceiverFeeGrowth(receiver);
        $.shortStateMap[marketId].syncReceiverFeeGrowth(receiver);
        return receiverBorrowingFee;
    }

    function _emitBorrowingFeeSettled(uint256 marketId, address trader, int256 pendingFeeToBeSettled) private {
        if (pendingFeeToBeSettled == 0) {
            return;
        }
        emit BorrowingFeeSettled(marketId, trader, pendingFeeToBeSettled);
    }

    function _emitUtilRatioChanged(
        uint256 marketId,
        uint256 newLongUtilRatio,
        uint256 newShortUtilRatio,
        uint256 oldLongUtilRatio,
        uint256 oldShortUtilRatio
    ) private {
        if (oldLongUtilRatio == newLongUtilRatio && oldShortUtilRatio == newShortUtilRatio) {
            return;
        }
        emit UtilRatioChanged(marketId, newLongUtilRatio, newShortUtilRatio, oldLongUtilRatio, oldShortUtilRatio);
    }

    function _getBorrowingFeeModelStorage() private pure returns (BorrowingFeeModelStorage storage $) {
        assembly {
            $.slot := _BORROWING_FEE_MODEL_STORAGE_LOCATION
        }
    }
}
