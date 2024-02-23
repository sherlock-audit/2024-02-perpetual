// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../src/vault/IPositionModelEvent.sol";
import "../../src/vault/LibPositionModel.sol";

contract LibPositionModelHarness {
    using LibPositionModel for PositionModelState;
    mapping(uint256 => PositionModelState) public state;

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function getPosition(uint256 marketId, address trader) public view returns (Position memory) {
        return state[marketId].positionMap[trader];
    }

    function getUnsettledPnl(uint256 marketId, address trader) external view returns (int256) {
        return getPosition(marketId, trader).unsettledPnl;
    }

    function getPnlPoolBalance(uint256 marketId) external view returns (uint256) {
        return state[marketId].pnlPoolBalance;
    }

    function getBadDebt(uint256 marketId) external view returns (uint256) {
        return state[marketId].badDebt;
    }

    function exposed_settlePnl(uint256 marketId, address trader, int256 realizedPnl) external returns (int256) {
        return state[marketId].settlePnl(trader, realizedPnl);
    }

    function exposed_updateBadDebt(
        uint256 marketId,
        int256 oldUnsettledPnl,
        int256 newUnsettledPnl
    ) external returns (int256) {
        return state[marketId].updateBadDebt(oldUnsettledPnl, newUnsettledPnl);
    }

    function exposed_setPnlPoolBalance(uint256 marketId, uint256 balance) external {
        state[marketId].pnlPoolBalance = balance;
    }

    function exposed_setBadDebt(uint256 marketId, uint256 badDebt) external {
        state[marketId].badDebt = badDebt;
    }

    function exposed_setMarginAndUnsettledPnl(
        uint256 marketId,
        address trader,
        uint256 margin,
        int256 unsettledPnl
    ) external {
        Position storage position = state[marketId].positionMap[trader];
        position.margin = margin;
        position.unsettledPnl = unsettledPnl;
    }

    function exposed_setPosition(uint256 marketId, address trader, int256 size, int256 openNotional) external {
        Position storage position = state[marketId].positionMap[trader];
        position.positionSize = size;
        position.openNotional = openNotional;
    }
}
