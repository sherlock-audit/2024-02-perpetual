// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../oracleMaker/OracleMakerIntSetup.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { LibError } from "../../src/common/LibError.sol";

contract OpenPositionWithOMInt is OracleMakerIntSetup {
    bytes public makerData;
    address public taker = makeAddr("taker");
    address public lp = makeAddr("lp");

    function setUp() public override {
        super.setUp();

        makerData = validPythUpdateDataItem;

        _mockPythPrice(150, 0);
        _deposit(marketId, taker, 1000e6);
        maker.setValidSender(taker, true);

        deal(address(collateralToken), address(lp), 2000e6, true);
        vm.startPrank(lp);
        collateralToken.approve(address(maker), 2000e6);
        maker.deposit(2000e6);
        vm.stopPrank();
    }

    function test_B2QExactInput() public {
        vm.startPrank(taker);

        // taker short 10 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );

        _assertEq(
            _getMarginProfile(marketId, taker, 150e18),
            LegacyMarginProfile({
                positionSize: -10 ether,
                openNotional: 1500 ether,
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 850 ether,
                freeCollateralForOpen: 850 ether, // min(1000, 1000) - 1500 * 0.1 = 850
                freeCollateralForReduce: 906.25 ether, // min(1000, 1000) - 1500 * 0.0625 = 906.25
                marginRatio: 666666666666666666
            })
        );
        _assertEq(
            _getMarginProfile(marketId, address(maker), 150e18),
            LegacyMarginProfile({
                positionSize: 10 ether,
                openNotional: -1500 ether,
                accountValue: 2000 ether,
                unrealizedPnl: 0,
                freeCollateral: 1850 ether,
                freeCollateralForOpen: 1850 ether, // min(2000, 2000) - 1500 * 0.1 = 1850
                freeCollateralForReduce: 1906.25 ether, // min(2000, 2000) - 1500 * 0.0625 = 1906.25
                marginRatio: 1333333333333333333
            })
        );
        vm.stopPrank();
    }

    function test_B2QExactOutput() public {
        vm.startPrank(taker);

        // taker short ether with 1500 usd
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: false,
                amount: 1500 ether,
                oppositeAmountBound: 20 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );

        _assertEq(
            _getMarginProfile(marketId, taker, 150e18),
            LegacyMarginProfile({
                positionSize: -10 ether,
                openNotional: 1500 ether,
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 850 ether,
                freeCollateralForOpen: 850 ether, // min(1000, 1000) - 1500 * 0.1 = 850
                freeCollateralForReduce: 906.25 ether, // min(1000, 1000) - 1500 * 0.0625 = 906.25
                marginRatio: 666666666666666666
            })
        );
        _assertEq(
            _getMarginProfile(marketId, address(maker), 150e18),
            LegacyMarginProfile({
                positionSize: 10 ether,
                openNotional: -1500 ether,
                accountValue: 2000 ether,
                unrealizedPnl: 0,
                freeCollateral: 1850 ether,
                freeCollateralForOpen: 1850 ether, // min(2000, 2000) - 1500 * 0.1 = 1850
                freeCollateralForReduce: 1906.25 ether, // min(2000, 2000) - 1500 * 0.0625 = 1906.25
                marginRatio: 1333333333333333333
            })
        );
        vm.stopPrank();
    }

    function test_Q2BExactInput() public {
        vm.startPrank(taker);

        // taker long ether with 1500 usd
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: true,
                amount: 1500 ether,
                oppositeAmountBound: 5 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );

        _assertEq(
            _getMarginProfile(marketId, taker, 150e18),
            LegacyMarginProfile({
                positionSize: 10 ether,
                openNotional: -1500 ether,
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 850 ether,
                freeCollateralForOpen: 850 ether, // min(1000, 1000) - 1500 * 0.1 = 850
                freeCollateralForReduce: 906.25 ether, // min(1000, 1000) - 1500 * 0.0625 = 906.25
                marginRatio: 666666666666666666
            })
        );
        _assertEq(
            _getMarginProfile(marketId, address(maker), 150e18),
            LegacyMarginProfile({
                positionSize: -10 ether,
                openNotional: 1500 ether,
                accountValue: 2000 ether,
                unrealizedPnl: 0,
                freeCollateral: 1850 ether,
                freeCollateralForOpen: 1850 ether, // min(2000, 2000) - 1500 * 0.1 = 1850
                freeCollateralForReduce: 1906.25 ether, // min(2000, 2000) - 1500 * 0.0625 = 1906.25
                marginRatio: 1333333333333333333
            })
        );
        vm.stopPrank();
    }

    function test_Q2BExactOutput() public {
        vm.startPrank(taker);

        // taker long 10 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );

        _assertEq(
            _getMarginProfile(marketId, taker, 150e18),
            LegacyMarginProfile({
                positionSize: 10 ether,
                openNotional: -1500 ether,
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 850 ether,
                freeCollateralForOpen: 850 ether, // min(1000, 1000) - 1500 * 0.1 = 850
                freeCollateralForReduce: 906.25 ether, // min(1000, 1000) - 1500 * 0.0625 = 906.25
                marginRatio: 666666666666666666
            })
        );
        _assertEq(
            _getMarginProfile(marketId, address(maker), 150e18),
            LegacyMarginProfile({
                positionSize: -10 ether,
                openNotional: 1500 ether,
                accountValue: 2000 ether,
                unrealizedPnl: 0,
                freeCollateral: 1850 ether,
                freeCollateralForOpen: 1850 ether, // min(2000, 2000) - 1500 * 0.1 = 1850
                freeCollateralForReduce: 1906.25 ether, // min(2000, 2000) - 1500 * 0.0625 = 1906.25
                marginRatio: 1333333333333333333
            })
        );
        vm.stopPrank();
    }

    function test_RevertIf_B2QWithInsufficientQuote() public {
        vm.startPrank(taker);

        vm.expectRevert(abi.encodeWithSelector(LibError.InsufficientOutputAmount.selector, 1500 ether, 2000 ether));
        // taker short 10 ether, expecting at least 2000 usd
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );
        vm.stopPrank();
    }

    function test_RevertIf_B2QWithExcessiveBase() public {
        vm.startPrank(taker);

        vm.expectRevert(abi.encodeWithSelector(LibError.ExcessiveInputAmount.selector, 10 ether, 5 ether));
        // taker short ether with 1500 usd, expecting at most 5 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: false,
                amount: 1500 ether,
                oppositeAmountBound: 5 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );
        vm.stopPrank();
    }

    function test_RevertIf_Q2BWithInsufficientBase() public {
        vm.startPrank(taker);

        vm.expectRevert(abi.encodeWithSelector(LibError.InsufficientOutputAmount.selector, 10 ether, 20 ether));
        // taker long with 1500 usd, expecting at least 20 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: true,
                amount: 1500 ether,
                oppositeAmountBound: 20 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );
        vm.stopPrank();
    }

    function test_RevertIf_Q2BWithExcessiveQuote() public {
        vm.startPrank(taker);

        vm.expectRevert(abi.encodeWithSelector(LibError.ExcessiveInputAmount.selector, 1500 ether, 1000 ether));
        // taker long 10 ether, expecting at most 1000 ether
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );
        vm.stopPrank();
    }
}
