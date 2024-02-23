// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "./OracleMakerIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";

contract OracleMakerFillOrderInt is OracleMakerIntSetup {
    address public lp = makeAddr("LiquidityProvider");
    address public taker = makeAddr("Taker");

    function setUp() public virtual override {
        super.setUp();
        maker.setMaxSpreadRatio(0.1 ether); // 10%
        maker.setValidSender(taker, true);

        // lp deposit 10000 to maker
        uint256 makerAmount = 10000e6;
        deal(address(collateralToken), lp, makerAmount, true);
        vm.startPrank(lp);
        collateralToken.approve(address(maker), makerAmount);
        maker.deposit(makerAmount);
        vm.stopPrank();

        // taker deposit 1000
        _deposit(marketId, taker, 1000e6);

        _mockPythPrice(1000, 0);
    }

    function test_one_sided_circuit_breaker_cannot_short() public {
        // taker open short position to reach maker's minMarginRatio
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 10000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        assertEq(_getMarginProfile(marketId, address(maker), 1000e18).marginRatio, 1 ether);

        // taker should not be able to open short position
        vm.prank(taker);
        // oracle price = 1000 * 90% (spread) = 900
        // maker's uPnl also increase $100 because of this spread
        // 10100 / 10900 = 0.926605504587155963
        vm.expectRevert(
            abi.encodeWithSelector(LibError.MinMarginRatioExceeded.selector, 0.926605504587155963 ether, 1 ether)
        );
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1 ether,
                oppositeAmountBound: 900 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker can reduce position == long without spread
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether, // no profit/loss since open/close at $1000
                positionSize: -9 ether,
                openNotional: 9000 ether,
                unsettledPnl: 0
            })
        );
    }

    function test_one_sided_circuit_breaker_cannot_long() public {
        // taker open long position to reach maker's minMarginRatio
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 10000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        assertEq(_getMarginProfile(marketId, address(maker), 1000e18).marginRatio, 1 ether);

        // taker should not be able to open long position
        vm.prank(taker);
        // 10,000 / 11,100 = 0.900901
        vm.expectRevert(
            abi.encodeWithSelector(LibError.MinMarginRatioExceeded.selector, 0.909909909909909909 ether, 1 ether)
        );
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 1100 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker can reduce position == short without spread
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 1000 ether, // no profit/loss since open/close at $1000
                positionSize: 9 ether,
                openNotional: -9000 ether,
                unsettledPnl: 0
            })
        );
    }

    function test_long_short_with_spread() public {
        // taker open long position without spread
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 1000 ether, positionSize: 1 ether, openNotional: -1000 ether, unsettledPnl: 0 })
        );

        // taker open long again with spread
        // maker maxPositionNotional = 10000 / 1 = 10000
        // maker posiitonNotional = -1 * 1000 = -1000
        // spreadRatio = 0.1 * (-1000 / 10000) = -0.01
        // priceWithSpread = 1000 * (1 - -0.01) = 1010
        vm.prank(taker);
        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.OMOrderFilled(marketId, 1000 ether, 1 ether, -1010 ether);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 1010 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 1000 ether, positionSize: 2 ether, openNotional: -2010 ether, unsettledPnl: 0 })
        );

        // taker open short position without spread
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 3 ether,
                oppositeAmountBound: 3000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 990 ether, // loss $10
                positionSize: -1 ether,
                openNotional: 1000 ether,
                unsettledPnl: 0
            })
        );
        // maker has profit $10, but vault.settlePosition() settles maker first, pnl pool is empty, so maker has unsettledPnl
        _assertEq(
            _getPosition(marketId, address(maker)),
            PositionProfile({
                margin: 10010 ether,
                positionSize: 1 ether,
                openNotional: -1000 ether,
                unsettledPnl: 10 ether // earn $10
            })
        );

        // taker open short again with spread
        vm.prank(taker);
        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.OMOrderFilled(marketId, 1000 ether, -3 ether, 2970029970029970030000);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 3 ether,
                oppositeAmountBound: 2970 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // maker maxPositionNotional = 10010 / 1 = 10010
        // maker posiitonNotional = 1 * 1000 = 1000
        // spreadRatio = 0.1 * (1000 / 10010) = 0.009990009990009992
        // priceWithSpread = 1000 * (1 - 0.009990009990009992) = 990.00999000999
        // openNotional = 1000 + 3 * 990.00999000999 ~= 3970.02997002997
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({
                margin: 990 ether,
                positionSize: -4 ether,
                openNotional: 3970029970029970030000,
                unsettledPnl: 0
            })
        );
    }
}
