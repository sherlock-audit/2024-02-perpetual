// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { TestMaker } from "../helper/TestMaker.sol";
import { LibError } from "../../src/common/LibError.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { IVault } from "../../src/vault/IVault.sol";
import { Vault } from "../../src/vault/Vault.sol";
import "./ClearingHouseIntSetup.sol";

contract LiquidateInt is ClearingHouseIntSetup {
    TestMaker public maker;
    address public taker = makeAddr("taker");
    address public liquidator = makeAddr("liquidator");

    function setUp() public override {
        super.setUp();

        vm.label(address(maker), "maker");
        vm.label(taker, "taker");
        vm.label(liquidator, "liquidator");

        maker = _newMarketWithTestMaker(marketId);
        maker.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);

        _deposit(marketId, address(maker), 10000e6);
        _deposit(marketId, taker, 1000e6);
        _deposit(marketId, liquidator, 2000e6);
    }

    function test_LiquidateLongFullNormal() public {
        // taker long 50 ether with 5x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(825, -1);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 82.5e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 82.5e18), 50 ether);

        // unrealizedPnl = -5000 + 50*82.5 = -875
        // accountValue = 1000 - 875 = 125
        // positionValue = 50*82.5 = 4125
        // marginRatio = 125 / 5000 = 2.5%
        // liquidate:
        // liquidated position size: 50
        // liquidated position notional: 50*82.5 = 4125
        // penalty = 5000 * 2.5% = 125
        // penalty to liquidator = 125 * 50% = 62.5
        // penalty to protocol = 125 * 50% = 62.5
        // margin = 1000 - 875 - 125 = 0

        // TODO @shao should event taker == maker when liquidate?
        // liquidator take over trader's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            50 ether, // positionSizeDelta
            -4125 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -875 ether, // realizedPnl = 50 * (100-82.5)
            -875 ether, // settledPnl
            125 ether,
            0 ether, // unsettledPnl
            875 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            -50 ether, // positionSizeDelta
            4125 ether, // openNotionalDelta
            -875 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 875 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            875 ether + 62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            2000 ether + 62.5 ether, // margin
            0 ether, // unsettledPnl
            875 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 875 ether - 62.5 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            875 ether + 62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            62.5 ether, // margin
            0 ether, // unsettledPnl
            875 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -50 ether,
            4125 ether,
            82.5 ether,
            125 ether,
            62.5 ether,
            62.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 875 ether - 125 ether,
                positionSize: 0,
                openNotional: 0,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 62.5 ether,
                positionSize: 50 ether,
                openNotional: -4125 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 62.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateLongMaximumLiquidatablePositionSize() public {
        // taker long 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio > 3.125% && margin ratio < 6.25%, liquidate half of the position
        _mockPythPrice(85, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 85e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 85e18), 25 ether);

        // unrealizedPnl = -5000 + 50*85 = -750
        // accountValue = 1000 - 750 = 250
        // positionValue = 50*85 = 4250
        // marginRatio = 250 / 4250 = 0.05882352941
        // liquidate:
        // liquidated position size: 25
        // liquidated position notional: 25 * 85 = 2125
        // releasedPnl: -2500 + 2125 = -375
        // penalty = 2500 * 2.5% = 62.5
        // margin = 1000 - 375 - 62.5 = 500

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            25 ether, // positionSizeDelta
            -2125 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -375 ether, // realizedPnl = 25 * (100-85)
            -375 ether, // settledPnl
            1000 ether - 375 ether, // margin
            0 ether, // unsettledPnl
            375 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            -25 ether, // positionSizeDelta
            2125 ether, // openNotionalDelta
            -375 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -31.25 ether, // realizedPnl = 2500 * 2.5% / 2
            -31.25 ether, // settledPnl
            1000 ether - 375 ether - 31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether + 31.25 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            31.25 ether, // realizedPnl = 62.5 * 0.5
            31.25 ether, // settledPnl
            2000 ether + 31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -31.25 ether, // realizedPnl = 2000 * 0.025 / 2
            -31.25 ether, // settledPnl
            1000 ether - 375 ether - 31.25 ether - 31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether + 31.25 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            31.25 ether, // realizedPnl = 125 * 0.5
            31.25 ether, // settledPnl
            31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -25 ether,
            2125 ether,
            85 ether,
            62.5 ether,
            31.25 ether,
            31.25 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        // margin = 1000 - 25 * (100 - 85) = 625
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 375 ether - 62.5 ether,
                positionSize: 25 ether,
                openNotional: -2500 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 31.25 ether,
                positionSize: 25 ether,
                openNotional: -2125 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 31.25 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateLongPartialLessThanMaximum() public {
        // taker long 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio > 3.125% && margin ratio < 6.25%, liquidate half of the position
        _mockPythPrice(85, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 85e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 85e18), 25 ether);

        // unrealizedPnl = -5000 + 50*85 = -750
        // accountValue = 1000 - 750 = 250
        // positionValue = 50*85 = 4250
        // marginRatio = 250 / 4250 = 0.05882352941
        // liquidate:
        // liquidated position size: 10
        // liquidated position notional: 10 * 85 = 850
        // penalty: 1000 * 2.5% = 25

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            10 ether, // positionSizeDelta
            -850 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -150 ether, // realizedPnl = 10 * (100-85)
            -150 ether, // settledPnl
            1000 ether - 150 ether, // margin
            0 ether, // unsettledPnl
            150 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            -10 ether, // positionSizeDelta
            850 ether, // openNotionalDelta
            -150 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -12.5 ether, // realizedPnl
            -12.5 ether, // settledPnl
            1000 ether - 150 ether - 12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether + 12.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            12.5 ether, // realizedPnl = 25 * 0.5
            12.5 ether, // settledPnl
            2000 ether + 12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -12.5 ether, // realizedPnl
            -12.5 ether, // settledPnl
            1000 ether - 150 ether - 12.5 ether - 12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether + 12.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            12.5 ether, // realizedPnl = 53.125 * 0.5
            12.5 ether, // settledPnl
            12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -10 ether,
            850 ether,
            85 ether,
            25 ether,
            12.5 ether,
            12.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 10 ether })
        );

        // margin = 1000 - 10 * (100 - 85) = 850
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 150 ether - 25 ether,
                positionSize: 40 ether,
                openNotional: -4000 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 12.5 ether,
                positionSize: 10 ether,
                openNotional: -850 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 12.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateLongFullWithBadDebt() public {
        // taker long 50 ether with 5x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(80, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 80e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 80e18), 50 ether);

        // unrealizedPnl = -5000 + 50*80 = -1000
        // accountValue = 1000 - 1000 = 0
        // positionValue = 50*80 = 4000
        // marginRatio = 0 / 4000 = 0
        // liquidate:
        // liquidated position size: 50
        // liquidated position notional: 4000
        // penalty = 5000 * 2.5% = 125

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            50 ether, // positionSizeDelta
            -4000 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -1000 ether, // realizedPnl = 50 * (100-80)
            -1000 ether, // settledPnl
            0 ether, // margin
            0 ether, // unsettledPnl
            1000 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            -50 ether, // positionSizeDelta
            4000 ether, // openNotionalDelta
            -1000 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            0 ether, // settledPnl
            0 ether, // margin
            -62.5 ether, // unsettledPnl
            1000 ether // pnlPoolBalance, NOTE: taker has no margin to pay penalty, so pnlPoolBalance won't increase
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            2000 ether + 62.5 ether, // margin
            0 ether, // unsettledPnl
            1000 ether - 62.5 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            0 ether, // settledPnl
            0 ether, // margin
            -62.5 ether - 62.5 ether, // unsettledPnl
            937.5 ether // pnlPoolBalance, NOTE: taker has no margin to pay penalty, so pnlPoolBalance won't increase
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            62.5 ether, // margin
            0 ether, // unsettledPnl
            937.5 ether - 62.5 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -50 ether,
            4000 ether,
            80 ether,
            125 ether,
            62.5 ether,
            62.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        // margin = 1000 - 50 * (100 - 80) = 0
        // but need to pay penalty 100, so final margin = -100
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: -125 ether, positionSize: 0, openNotional: 0, unsettledPnl: -125 ether })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 62.5 ether,
                positionSize: 50 ether,
                openNotional: -4000 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 62.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );

        assertEq(vault.getBadDebt(marketId), 125 ether);
    }

    function test_liquidate_Short_Full_Normal() public {
        // taker short 50 ether with 5x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 50 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(117, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 117e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 117e18), -50 ether);

        // unrealizedPnl = 5000 - 50*117 = -850
        // accountValue = 1000 - 850 = 150
        // positionValue = 50*117 = 5850
        // marginRatio = 150 / 5850 = 0.02564102564
        // liquidate:
        // liquidated position size: 50
        // liquidated position notional: 50*117 = 5850
        // penalty = 5000 * 2.5% = 125
        // margin = 1000 -850 -125 = 25

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            -50 ether, // positionSizeDelta
            5850 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -850 ether, // realizedPnl = 50 * (100-117)
            -850 ether, // settledPnl
            1000 ether - 850 ether, // margin
            0 ether, // unsettledPnl
            850 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            50 ether, // positionSizeDelta
            -5850 ether, // openNotionalDelta
            -850 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 850 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            850 ether + 62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            2000 ether + 62.5 ether, // margin
            0 ether, // unsettledPnl
            850 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 850 ether - 62.5 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            850 ether + 62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            62.5 ether, // margin
            0 ether, // unsettledPnl
            850 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            50 ether,
            -5850 ether,
            117 ether,
            125 ether,
            62.5 ether,
            62.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 850 ether - 125 ether,
                positionSize: 0,
                openNotional: 0,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 62.5 ether,
                positionSize: -50 ether,
                openNotional: 5850 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 62.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateShortMaximumLiquidatablePositionSize() public {
        // taker short 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio > 3.125% && margin ratio < 6.25%, liquidate half of the position
        _mockPythPrice(115, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 115e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 115e18), -25 ether);

        // unrealizedPnl = 5000 - 50*115 = -750
        // accountValue = 1000 - 750 = 250
        // positionValue = 50*115 = 5750
        // marginRatio = 250 / 5750 = 0.04347826087
        // liquidate:
        // liquidated position size: 25
        // liquidated position notional: 25 * 115 = 2875
        // releasedPnl: 2500 - 2875 = -375
        // penalty = 2500 * 2.5% = 62.5
        // margin = 1000 - 375 - 62.5 = 562.5

        // liquidator take over trader's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            -25 ether, // positionSizeDelta
            2875 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -375 ether, // realizedPnl
            -375 ether, // settledPnl
            1000 ether - 375 ether, // margin
            0 ether, // unsettledPnl
            375 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            25 ether, // positionSizeDelta
            -2875 ether, // openNotionalDelta
            -375 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -31.25 ether, // realizedPnl = 2875 * 0.025
            -31.25 ether, // settledPnl
            1000 ether - 375 ether - 31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether + 31.25 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            31.25 ether, // realizedPnl = 62.5 * 0.5
            31.25 ether, // settledPnl
            2000 ether + 31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -31.25 ether, // realizedPnl = 2875 * 0.025
            -31.25 ether, // settledPnl
            1000 ether - 375 ether - 31.25 ether - 31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether + 31.25 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            31.25 ether, // realizedPnl = 62.5  * 0.5
            31.25 ether, // settledPnl
            31.25 ether, // margin
            0 ether, // unsettledPnl
            375 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            25 ether,
            -2875 ether,
            115 ether,
            62.5 ether,
            31.25 ether,
            31.25 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        // margin = 1000 - 25 * (100 - 85) = 625
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 375 ether - 62.5 ether,
                positionSize: -25 ether,
                openNotional: 2500 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 31.25 ether,
                positionSize: -25 ether,
                openNotional: 2875 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 31.25 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateShortPartialLessThanMaximum() public {
        // taker short 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 50 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio > 3.125% && margin ratio < 6.25%, liquidate half of the position
        _mockPythPrice(115, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 115e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 115e18), -25 ether);

        // unrealizedPnl = 5000 - 50*115 = -750
        // accountValue = 1000 - 750 = 250
        // positionValue = 50*115 = 5750
        // marginRatio = 250 / 5750 = 0.04347826087
        // liquidate:
        // liquidated position size: 10
        // liquidated position notional: 10 * 115 = 1150
        // penalty: 1000 * 2.5% = 25

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            -10 ether, // positionSizeDelta
            1150 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -150 ether, // realizedPnl = 10 * (115-100)
            -150 ether, // settledPnl
            1000 ether - 150 ether, // margin
            0 ether, // unsettledPnl
            150 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            10 ether, // positionSizeDelta
            -1150 ether, // openNotionalDelta
            -150 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -12.5 ether, // realizedPnl
            -12.5 ether, // settledPnl
            1000 ether - 150 ether - 12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether + 12.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            12.5 ether, // realizedPnl = 25 * 0.5
            12.5 ether, // settledPnl
            2000 ether + 12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -12.5 ether, // realizedPnl
            -12.5 ether, // settledPnl
            1000 ether - 150 ether - 12.5 ether - 12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether + 12.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            12.5 ether, // realizedPnl = 25 * 0.5
            12.5 ether, // settledPnl
            12.5 ether, // margin
            0 ether, // unsettledPnl
            150 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            10 ether, // positionSizeDelta
            -1150 ether, // positionNotionalDelta
            115 ether, // price
            25 ether, // penalty
            12.5 ether, // liquidationFeeToLiquidator
            12.5 ether // liquidationFeeToProtocol
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 10 ether })
        );

        // margin = 1000 - 10 * (115 - 100) = 850
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 150 ether - 25 ether,
                positionSize: -40 ether,
                openNotional: 4000 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 12.5 ether,
                positionSize: -10 ether,
                openNotional: 1150 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 12.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateShortFullWithBadDebt() public {
        // taker short 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 50 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(120, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 120e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 120e18), -50 ether);

        // unrealizedPnl = 5000 - 50*120 = -1000
        // accountValue = 1000 - 1000 = 0
        // positionValue = 50*120 = 6000
        // marginRatio = 0 / 6000 = 0
        // liquidate:
        // liquidated position size: 50
        // liquidated position notional: 6000
        // penalty = 5000 * 2.5% = 125

        // liquidator take over trader's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            -50 ether, // positionSizeDelta
            6000 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -1000 ether, // realizedPnl = 50 * (100-80)
            -1000 ether, // settledPnl
            0 ether, // margin
            0 ether, // unsettledPnl
            1000 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            50 ether, // positionSizeDelta
            -6000 ether, // openNotionalDelta
            -1000 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            0 ether, // settledPnl
            0 ether, // margin
            -62.5 ether, // unsettledPnl
            1000 ether // pnlPoolBalance, NOTE: taker has no margin to pay penalty, so pnlPoolBalance won't increase
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            2000 ether + 62.5 ether, // margin
            0 ether, // unsettledPnl
            1000 ether - 62.5 ether // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            0 ether, // settledPnl
            0 ether, // margin
            -125 ether, // unsettledPnl
            1000 ether - 62.5 ether // pnlPoolBalance, NOTE: taker has no margin to pay penalty, so pnlPoolBalance won't increase
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            62.5 ether, // margin
            0 ether, // unsettledPnl
            1000 ether - 125 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            50 ether,
            -6000 ether,
            120 ether,
            125 ether,
            62.5 ether,
            62.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: -125 ether, positionSize: 0, openNotional: 0, unsettledPnl: -125 ether })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 62.5 ether,
                positionSize: -50 ether,
                openNotional: 6000 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 62.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );

        assertEq(vault.getBadDebt(marketId), 125 ether);
    }

    function test_LiquidateLongFullWhenLiquidatorHasExistingShortPosition() public {
        // liquidator short 50 ether
        vm.prank(liquidator);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 50 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker long 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(825, -1);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 82.5e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 82.5e18), 50 ether);

        // unrealizedPnl = -5000 + 50*82.5 = -875
        // accountValue = 1000 - 875 = 125
        // positionValue = 50*82.5 = 4125
        // marginRatio = 125 / 4125 = 0.0303030303
        // liquidate:
        // liquidated position size: 50
        // liquidated position notional: 50*82.5 = 4125
        // penalty = 4125 * 2.5% = 125
        // margin = 1000 -875 -125 = 21.875

        // for liquidator
        // openNotional = 5000
        // positionValue = -50 * 82.5 = -4125
        // realizedPnl =  5000-4125 = 875

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            875 ether, // realizedPnl = 50 * (100-82.5)
            0 ether, // settledPnl
            2000 ether, // margin
            875 ether, // unsettledPnl
            0 // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            50 ether, // positionSizeDelta
            -4125 ether, // openNotionalDelta
            875 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -875 ether, // realizedPnl = 50 * (100-82.5)
            -875 ether, // settledPnl
            1000 ether - 875 ether, // margin
            0 ether, // unsettledPnl
            875 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            -50 ether, // positionSizeDelta
            4125 ether, // openNotionalDelta
            -875 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 875 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            875 ether + 62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            62.5 ether, // realizedPnl
            875 ether + 62.5 ether, // settledPnl
            2000 ether + 875 ether + 62.5 ether, // margin
            0 ether, // unsettledPnl
            0 ether // pnlPoolBalance
        );

        // taker pay penalty to to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 875 ether - 62.5 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            62.5 ether, // margin
            0 ether, // unsettledPnl
            0 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -50 ether,
            4125 ether,
            82.5 ether,
            125 ether,
            62.5 ether,
            62.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 875 ether - 125 ether,
                positionSize: 0,
                openNotional: 0,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 875 ether + 62.5 ether,
                positionSize: 0,
                openNotional: 0,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 62.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateShortFullWhenLiquidatorHasExistingLongPosition() public {
        // liquidator long 50 ether
        vm.prank(liquidator);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker short 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 50 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(117, 0);
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 117e18), true);
        assertEq(clearingHouse.getLiquidatablePositionSize(marketId, taker, 117e18), -50 ether);

        // unrealizedPnl = 5000 - 50*117 = -850
        // accountValue = 1000 - 850 = 150
        // positionValue = 50*117 = 5850
        // marginRatio = 150 / 5850 = 0.02564102564
        // liquidate:
        // liquidated position size: 50
        // liquidated position notional: 50*117 = 5850
        // penalty = 5850 * 2.5% = 125
        // margin = 1000 -850 -125 = 25

        // for liquidator
        // open notional: -5000
        // realizedPnl: -5000 + 50*117 = 850

        // liquidator take over taker's position
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            850 ether, // realizedPnl = 50 * (100-117)
            0 ether, // settledPnl
            2000 ether, // margin
            850 ether, // unsettledPnl
            0 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(liquidator),
            address(liquidator),
            -50 ether, // positionSizeDelta
            5850 ether, // openNotionalDelta
            850 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -850 ether, // realizedPnl = 50 * (100-117)
            -850 ether, // settledPnl
            1000 ether - 850 ether, // margin
            0 ether, // unsettledPnl
            850 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(liquidator),
            50 ether, // positionSizeDelta
            -5850 ether, // openNotionalDelta
            -850 ether, // realizedPnl
            PositionChangedReason.Liquidate // reason
        );

        // taker pay penalty to liquidator
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 850 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            850 ether + 62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(liquidator),
            62.5 ether, // realizedPnl
            850 ether + 62.5 ether, // settledPnl
            2000 ether + 850 ether + 62.5 ether, // margin
            0 ether, // unsettledPnl
            0 // pnlPoolBalance
        );

        // taker pay penalty to protocol
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            -62.5 ether, // realizedPnl
            -62.5 ether, // settledPnl
            1000 ether - 850 ether - 62.5 ether - 62.5 ether, // margin
            0 ether, // unsettledPnl
            62.5 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(clearingHouse),
            62.5 ether, // realizedPnl
            62.5 ether, // settledPnl
            62.5 ether, // margin
            0 ether, // unsettledPnl
            0 ether // pnlPoolBalance
        );

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            50 ether,
            -5850 ether,
            117 ether,
            125 ether,
            62.5 ether,
            62.5 ether
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether - 850 ether - 125 ether,
                positionSize: 0,
                openNotional: 0,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 850 ether + 62.5 ether,
                positionSize: 0,
                openNotional: 0,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 62.5 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateLongFullWhenLiquidationFeeRatio_100_Percent() public {
        config.setLiquidationFeeRatio(marketId, 1e18); // 100%

        // taker long 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(825, -1);

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -50 ether,
            4125 ether,
            82.5 ether,
            125 ether,
            125 ether, // 100% of liquidation penalty goes to liquidator
            0
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({
                margin: 2000 ether + 125 ether,
                positionSize: 50 ether,
                openNotional: -4125 ether,
                unsettledPnl: 0
            })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 0, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidateLongFullWhenLiquidationFeeRatio_0_Percent() public {
        config.setLiquidationFeeRatio(marketId, 0); // 0%

        // taker long 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // price goes down, taker is liquidatable
        // margin ratio < 3.125%, liquidate the entire position
        _mockPythPrice(825, -1);

        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -50 ether,
            4125 ether,
            82.5 ether,
            125 ether,
            0,
            125 ether // 100% of liquidation penalty goes to protocol
        );

        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );

        _assertEq(
            _getPosition(marketId, liquidator),
            PositionProfile({ margin: 2000 ether, positionSize: 50 ether, openNotional: -4125 ether, unsettledPnl: 0 })
        );

        _assertEq(
            _getPosition(marketId, address(clearingHouse)),
            PositionProfile({ margin: 125 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_LiquidatorReducingPositionAndBelowIMRatio() public {
        // set price to 120
        maker.setBaseToQuotePrice(120e18);
        _mockPythPrice(120, 0);

        // liquidator long 80 eth
        vm.prank(liquidator);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 80 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // set price to 100
        maker.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);

        // taker short 100 ether with 10x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 100e18), false);

        // set price to 105
        _mockPythPrice(105, 0);
        // taker margin ratio = (1000 - 100 * 5) / (105 * 100) = 0.0476190476
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 105e18), true);
        // liquidator margin ratio = (2000 - 80 * 15) / (105 * 80) = 0.0952380952
        assertLt(_getMarginProfile(marketId, liquidator, 105e18).marginRatio, 0.1e18);

        // liquidator reduce position by liquidating taker's position
        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 10 ether })
        );
    }

    function test_RevertIf_NotLiquidatable() public {
        // taker long 50 ether with 5x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertFalse(clearingHouse.isLiquidatable(marketId, taker, 100e18));

        vm.expectRevert(abi.encodeWithSelector(LibError.NotLiquidatable.selector, marketId, taker));
        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 50 ether })
        );
    }

    function test_RevertIf_CannotLiquidateWhitelistedMaker() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.CannotLiquidateWhitelistedMaker.selector));
        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({
                marketId: marketId,
                trader: address(maker),
                positionSize: 50 ether
            })
        );
    }

    function test_RevertIf_LiquidatorIncreasingPositionAndBelowIMRatio() public {
        // set price to 120
        maker.setBaseToQuotePrice(120e18);
        _mockPythPrice(120, 0);

        // liquidator long 80 eth
        vm.prank(liquidator);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 80 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // set price to 110
        maker.setBaseToQuotePrice(110e18);
        _mockPythPrice(110, 0);

        // taker long ether with 10x leverate
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 90.9 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        assertEq(clearingHouse.isLiquidatable(marketId, taker, 110e18), false);

        // set price to 105
        _mockPythPrice(105, 0);
        // taker margin ratio = (1000 - 90.9 * 5) / (105 * 90.9) = 0.0571533344
        assertEq(clearingHouse.isLiquidatable(marketId, taker, 105e18), true);
        // liquidator margin ratio = (2000 - 80 * 15) / (105 * 80) = 0.0952380952
        assertLt(_getMarginProfile(marketId, liquidator, 105e18).marginRatio, 0.1e18);

        // liquidator increase position by liquidating taker's position, but not enough margin
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, liquidator));
        vm.prank(liquidator);
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 10 ether })
        );
    }

    function test_TradeStatsNotChangedAfterLiquidation() public {
        // taker long against whitelisted maker
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base, long
                isExactInput: false, // exact base
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // price goes down, taker is liquidatable
        _mockPythPrice(1, -1); // $0.1

        // cached total taker stats
        (LibUtilizationGlobal.Info memory oldLongGlobal, LibUtilizationGlobal.Info memory oldShortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);

        // when liquidate
        vm.prank(liquidator);
        vm.expectEmit(true, true, true, true, address(clearingHouse));
        emit IClearingHouse.Liquidated(
            marketId,
            liquidator,
            taker,
            -1 ether,
            0.1 ether, // openNotionalDelta
            0.1 ether,
            2.5 ether,
            1.25 ether,
            1.25 ether
        );
        clearingHouse.liquidate(
            IClearingHouse.LiquidatePositionParams({ marketId: marketId, trader: taker, positionSize: 1 ether })
        );

        // total taker size won't change, it's just transferring between takers
        // total taker open notional changed: increase 0.1 reduce 100 = -99.9
        // short remains the same
        (LibUtilizationGlobal.Info memory newLongGlobal, LibUtilizationGlobal.Info memory newShortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(oldLongGlobal.totalReceiverOpenNotional, newLongGlobal.totalReceiverOpenNotional);
        assertEq(oldLongGlobal.totalOpenNotional - 99.9 ether, newLongGlobal.totalOpenNotional);
        _assertEq(oldShortGlobal, newShortGlobal);
    }
}
