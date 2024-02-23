// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "./TestPositionModel.sol";
import "../../src/vault/PositionChangedReason.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract PositionModelHarness is PositionModelUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function exposed_POSITION_MODEL_STORAGE_LOCATION() external view returns (bytes32) {
        return _POSITION_MODEL_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract PositionModelSpec is Test, IPositionModelEvent, ERC7201Location {
    PositionModelHarness public positionModelHarness;
    TestPositionModel public posModel;
    uint256 public marketId = 0;
    address public taker = makeAddr("taker");
    address public maker = makeAddr("maker");

    function setUp() public {
        positionModelHarness = new PositionModelHarness();
        posModel = new TestPositionModel();
    }

    //
    // HELPER
    //
    function _addPos(int256 size, int256 openNotional) internal {
        posModel.addPosition(
            PositionModelUpgradeable.AddPositionParams({
                marketId: marketId,
                trader: taker,
                maker: maker,
                positionSizeDelta: size,
                openNotionalDelta: openNotional,
                reason: PositionChangedReason.Trade
            })
        );
    }

    //
    // TEST
    //

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            positionModelHarness.exposed_POSITION_MODEL_STORAGE_LOCATION(),
            getLocation("perp.storage.positionModel")
        );
    }

    function test_UpdateMargin() public {
        vm.expectEmit(true, true, true, true, address(posModel));
        emit MarginChanged(marketId, taker, 1);
        posModel.updateMargin(marketId, taker, 1);

        vm.expectEmit(true, true, true, true, address(posModel));
        emit MarginChanged(marketId, taker, -1);
        posModel.updateMargin(marketId, taker, -1);
    }

    function test_AddPosition() public {
        // taker long
        vm.expectEmit(true, true, true, true, address(posModel));
        emit PositionChanged(
            marketId,
            taker,
            maker,
            1, // size
            -1, // openNotional
            0, // realizedPnl
            PositionChangedReason.Trade
        );
        _addPos(1, -1);

        // then close with 1 profit
        vm.expectEmit(true, true, true, true, address(posModel));
        emit PositionChanged(
            marketId,
            taker,
            maker,
            -1, // size
            2, // openNotional
            1, // realizedPnl
            PositionChangedReason.Trade
        );
        _addPos(-1, 2);
    }

    function test_SettlePnl_Profit() public {
        vm.expectEmit(true, true, true, true, address(posModel));
        emit PnlSettled(
            marketId,
            taker,
            1, // realizedPnl
            0, // settledPnl
            0, // margin
            1, // unsettledPnl
            0 // pnlPoolBalance
        );
        posModel.settlePnl(marketId, taker, 1);
    }

    function test_SettlePnl_Loss() public {
        vm.expectEmit(true, true, true, true, address(posModel));
        emit PnlSettled(
            marketId,
            taker,
            -1, // realizedPnl
            0, // settledPnl
            0, // margin
            -1, // unsettledPnl
            0 // pnlPoolBalance
        );
        posModel.settlePnl(marketId, taker, -1);
    }
}
