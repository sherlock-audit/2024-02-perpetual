// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../src/vault/PositionModelUpgradeable.sol";

contract TestPositionModel is PositionModelUpgradeable {
    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function addPosition(AddPositionParams memory params) external {
        _addPosition(params);
    }

    function updateMargin(uint256 marketId, address trader, int256 marginDelta) external {
        _updateMargin(marketId, trader, marginDelta);
    }

    function settlePnl(uint256 marketId, address trader, int256 realizedPnl) external {
        _settlePnl(marketId, trader, realizedPnl);
    }

    function getBadDebt(uint256 marketId) external view virtual returns (uint256) {
        return _getBadDebt(marketId);
    }

    function getPnlPoolBalance(uint256 marketId) external view virtual returns (uint256) {
        return _getPnlPoolBalance(marketId);
    }

    function getPositionSize(uint256 marketId, address trader) external view virtual returns (int256) {
        return _getPositionSize(marketId, trader);
    }

    function getPosition(uint256 marketId, address trader) external view returns (Position memory) {
        return
            Position({
                positionSize: _getPositionSize(marketId, trader),
                openNotional: _getOpenNotional(marketId, trader),
                unsettledPnl: _getUnsettledPnl(marketId, trader),
                margin: _getMarginState(marketId, trader)
            });
    }

    function getOpenNotional(uint256 marketId, address trader) external view virtual returns (int256) {
        return _getOpenNotional(marketId, trader);
    }

    function getMarginState(uint256 marketId, address trader) external view virtual returns (uint256) {
        return _getMarginState(marketId, trader);
    }

    function getUnsettledPnl(uint256 marketId, address trader) external view virtual returns (int256) {
        return _getUnsettledPnl(marketId, trader);
    }

    function getSettledMargin(uint256 marketId, address trader) external view virtual returns (int256) {
        return _getSettledMargin(marketId, trader);
    }

    function getFreeMargin(
        uint256 marketId,
        address trader,
        int256 pendingMargin
    ) external view virtual returns (uint256) {
        return _getFreeMargin(marketId, trader, pendingMargin);
    }
}
