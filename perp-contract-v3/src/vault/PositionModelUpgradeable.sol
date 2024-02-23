// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IPositionModelEvent } from "./IPositionModelEvent.sol";
import { LibPositionModel } from "./LibPositionModel.sol";
import { LibPosition } from "./LibPosition.sol";
import { LibMargin } from "./LibMargin.sol";
import { PositionChangedReason } from "./PositionChangedReason.sol";
import { PositionModelState, Position } from "./PositionModelStruct.sol";

/// @dev the only entry point to get & set LibPositionModel.State. The only place to emit IPositionModelEvent
abstract contract PositionModelUpgradeable is Initializable, IPositionModelEvent {
    using LibPositionModel for PositionModelState;
    using LibPosition for Position;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.positionModel
    struct PositionModelStorage {
        // key: marketId
        mapping(uint256 => PositionModelState) stateMap;
    }

    struct AddPositionParams {
        uint256 marketId;
        address trader;
        address maker;
        int256 positionSizeDelta;
        int256 openNotionalDelta;
        PositionChangedReason reason;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.positionModel")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _POSITION_MODEL_STORAGE_LOCATION =
        0xcb3012114ec89fe4ad684e6d4c1df43eb7abe7cd33ce56b5cdde034b0faa5000;

    //
    // INIT
    //
    function __PositionModel_init() internal onlyInitializing {}

    //
    // INTERNAL
    //

    /// @notice caller has to ensure openNotionalDelta is non zero
    function _addPosition(AddPositionParams memory params) internal {
        Position storage position = _getPositionModelStorage().stateMap[params.marketId].positionMap[params.trader];
        int256 realizedPnl = position.add(params.positionSizeDelta, params.openNotionalDelta);
        _settlePnl(params.marketId, params.trader, realizedPnl);

        emit PositionChanged(
            params.marketId,
            params.trader,
            params.maker,
            params.positionSizeDelta,
            params.openNotionalDelta,
            realizedPnl,
            params.reason
        );
    }

    /// @param marginDelta in INTERNAL_DECIMALS
    function _updateMargin(uint256 marketId, address trader, int256 marginDelta) internal {
        _getPositionModelStorage().stateMap[marketId].positionMap[trader].updateMargin(marginDelta);
        emit MarginChanged(marketId, trader, marginDelta);
    }

    /// @param realizedPnl how much profit and loss in trader's perspective
    function _settlePnl(uint256 marketId, address trader, int256 realizedPnl) internal {
        PositionModelState storage state = _getPositionModelStorage().stateMap[marketId];
        Position storage position = state.positionMap[trader];

        int256 oldUnsettledPnl = position.unsettledPnl;
        int256 settledPnl = state.settlePnl(trader, realizedPnl);
        int256 newUnsettledPnl = position.unsettledPnl;

        _updateMargin(marketId, trader, settledPnl);
        _updateBadDebt(marketId, oldUnsettledPnl, newUnsettledPnl);

        // margin before settle = position.margin - settledPnl
        // unsettlePnl before settle = newUnsettledPnl - realizedPnl + settledPnl;
        emit PnlSettled(
            marketId,
            trader,
            realizedPnl,
            settledPnl,
            _getMarginState(marketId, trader),
            _getUnsettledPnl(marketId, trader),
            _getPnlPoolBalance(marketId)
        );
    }

    //
    // INTERNAL VIEW
    //
    function _getBadDebt(uint256 marketId) internal view virtual returns (uint256) {
        return _getPositionModelStorage().stateMap[marketId].badDebt;
    }

    function _getPnlPoolBalance(uint256 marketId) internal view virtual returns (uint256) {
        return _getPositionModelStorage().stateMap[marketId].pnlPoolBalance;
    }

    function _getPositionSize(uint256 marketId, address trader) internal view virtual returns (int256) {
        return _getPositionModelStorage().stateMap[marketId].positionMap[trader].positionSize;
    }

    function _getOpenNotional(uint256 marketId, address trader) internal view virtual returns (int256) {
        return _getPositionModelStorage().stateMap[marketId].positionMap[trader].openNotional;
    }

    function _getMarginState(uint256 marketId, address trader) internal view virtual returns (uint256) {
        return _getPositionModelStorage().stateMap[marketId].positionMap[trader].margin;
    }

    function _getUnsettledPnl(uint256 marketId, address trader) internal view virtual returns (int256) {
        return _getPositionModelStorage().stateMap[marketId].positionMap[trader].unsettledPnl;
    }

    function _getSettledMargin(uint256 marketId, address trader) internal view virtual returns (int256) {
        Position memory position = _getPositionModelStorage().stateMap[marketId].positionMap[trader];
        return LibMargin.getSettledMargin(position.margin, position.unsettledPnl);
    }

    function _getFreeMargin(
        uint256 marketId,
        address trader,
        int256 pendingMargin
    ) internal view virtual returns (uint256) {
        PositionModelState storage state = _getPositionModelStorage().stateMap[marketId];
        Position memory position = state.positionMap[trader];
        return LibMargin.getFreeMargin(position.margin, pendingMargin, position.unsettledPnl, state.pnlPoolBalance);
    }

    //
    // PRIVATE
    //

    function _updateBadDebt(uint256 marketId, int256 oldUnsettledPnl, int256 newUnsettledPnl) private {
        int256 badDebtDelta = _getPositionModelStorage().stateMap[marketId].updateBadDebt(
            oldUnsettledPnl,
            newUnsettledPnl
        );
        if (badDebtDelta != 0) {
            emit BadDebtChanged(marketId, badDebtDelta);
        }
    }

    function _getPositionModelStorage() private pure returns (PositionModelStorage storage $) {
        assembly {
            $.slot := _POSITION_MODEL_STORAGE_LOCATION
        }
    }
}
