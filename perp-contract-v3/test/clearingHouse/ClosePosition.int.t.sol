// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { TestMaker } from "../helper/TestMaker.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { IVault } from "../../src/vault/IVault.sol";
import "./ClearingHouseIntSetup.sol";

contract ClosePositionInt is ClearingHouseIntSetup {
    TestMaker public maker;
    address public taker = makeAddr("taker");

    function setUp() public override {
        super.setUp();

        maker = _newMarketWithTestMaker(marketId);
        maker.setBaseToQuotePrice(150e18);
        _mockPythPrice(150, 0);

        _deposit(marketId, address(maker), 10000e6);
        _deposit(marketId, taker, 1000e6);
    }

    function test_ClosePositionLongNormal() public {
        vm.startPrank(taker);

        // taker long 1 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 150 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        _assertEq(
            _getMarginProfile(marketId, taker, 150 ether), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 1 ether,
                openNotional: -150 ether, // Due to slippage (spot price = 2000)
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 985 ether,
                freeCollateralForOpen: 985 ether, // min(1000, 1000) - 150 * 1 * 0.1 = 985
                freeCollateralForReduce: 990.625 ether, // min(1000, 1000) - 150 * 1 * 0.0625 = 990.625
                marginRatio: 6666666666666666666
            })
        );

        maker.setBaseToQuotePrice(100e18);

        // taker close

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(maker),
            address(maker),
            1 ether, // positionSizeDelta
            -100 ether, // openNotionalDelta
            50 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(maker),
            -1 ether, // positionSizeDelta
            100 ether, // openNotionalDelta
            -50 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );

        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // Taker realized loss = 100 - 150 = -50
        // Taker margin after close = 1000 - 50 = 950

        _assertEq(
            _getMarginProfile(marketId, taker, 0), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 950 ether,
                unrealizedPnl: 0,
                freeCollateral: 950 ether,
                freeCollateralForOpen: 950 ether, // min(950, 950) - 0 = 950
                freeCollateralForReduce: 950 ether, // min(950, 950) - 0 = 950
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );

        vm.stopPrank();
    }

    function test_ClosePositionLongWhenMakerIsReducingAndBelowIMRatio() public {
        _deposit(marketId, taker, 20000e6);
        maker.setBaseToQuotePrice(1000e18);
        _mockPythPrice(1000, 0);

        vm.startPrank(taker);
        // taker long 100 ether, maker short 100 ether with max leverage
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // (10000 - 100*50) / (100 * 1050) = 0.0476190476
        uint256 newPrice = 1050e18;
        maker.setBaseToQuotePrice(newPrice);
        _mockPythPrice(1050, 0);

        // margin ratio below IM ratio (10%)
        assertLt(_getMarginProfile(marketId, address(maker), newPrice).marginRatio, 0.1e18);

        // taker close
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        vm.stopPrank();
    }

    function test_ClosePositionShortNormal() public {
        vm.startPrank(taker);

        // taker short 1 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1 ether,
                oppositeAmountBound: 150 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        _assertEq(
            _getMarginProfile(marketId, taker, 150 ether), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: -1 ether,
                openNotional: 150 ether, // Due to slippage (spot price = 2000)
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 985 ether,
                freeCollateralForOpen: 985 ether, // min(1000, 1000) - 150 * 1 * 0.1 = 985
                freeCollateralForReduce: 990.625 ether, // min(1000, 1000) - 150 * 1 * 0.0625 = 990.625
                marginRatio: 6666666666666666666
            })
        );

        maker.setBaseToQuotePrice(200e18);

        // taker close
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // Taker realized loss = 150 - 200 = -50
        // Taker margin after close = 1000 - 50 = 950

        _assertEq(
            _getMarginProfile(marketId, taker, 0), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 950 ether,
                unrealizedPnl: 0,
                freeCollateral: 950 ether,
                freeCollateralForOpen: 950 ether, // min(950, 950) - 0 = 950
                freeCollateralForReduce: 950 ether, // min(950, 950) - 0 = 950
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );

        vm.stopPrank();
    }

    function test_ClosePositionShortWhenMakerIsReducingAndBelowIMRatio() public {
        _deposit(marketId, taker, 20000e6);
        maker.setBaseToQuotePrice(1000e18);
        _mockPythPrice(1000, 0);

        vm.startPrank(taker);
        // taker short 100 ether, maker long 100 ether with max leverage
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

        // (10000 - 100*50) / (100 * 950) = 0.0526315789
        uint256 newPrice = 950e18;
        maker.setBaseToQuotePrice(newPrice);
        _mockPythPrice(950, 0);

        // margin ratio below IM ratio (10%)
        assertLt(_getMarginProfile(marketId, address(maker), newPrice).marginRatio, 0.1e18);

        // taker close
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        vm.stopPrank();
    }
}
