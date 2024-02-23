// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./OrderGatewayIntSetup.sol";
import { OrderGateway } from "../../src/orderGateway/OrderGateway.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { Config } from "../../src/config/Config.sol";
import { Vault } from "../../src/vault/Vault.sol";

import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract ExecuteOrderInt is OrderGatewayIntSetup {
    address taker = makeAddr("taker");
    address keeper = makeAddr("keeper");
    uint256 defaultMargin = 100e6;

    function setUp() public override {
        super.setUp();
        _deposit(marketId, address(maker), 10000e6);
        maker.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);

        // prepare taker funds
        deal(address(collateralToken), taker, defaultMargin);

        vm.startPrank(taker);
        clearingHouse.setAuthorization(address(orderGateway), true);
        vault.setAuthorization(address(orderGateway), true);
        vm.stopPrank();
    }

    function test_Succeed() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        _deposit(marketId, taker, defaultMargin);
        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderExecuted(0, taker, marketId, keeper, abi.encode(delayedOrder));
        vm.prank(keeper);
        orderGateway.executeOrder(0, "");

        assertEq(orderGateway.getOrdersCount(), 0);

        // check taker margin
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 100 ether, positionSize: -1, openNotional: 100, unsettledPnl: 0 })
        );
    }

    // NOTE: order gateway will not deposit / withdraw for user anymore
    function test_ExecuteOrderWithClosePosition() public {
        _deposit(marketId, taker, 1000e6);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(config.owner());
        config.setOrderDelaySeconds(60);

        bytes memory data = abi.encode(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );
        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.ClosePosition, data);

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderExecuted(0, taker, marketId, keeper, abi.encode(delayedOrder));

        vm.prank(keeper);
        orderGateway.executeOrder(0, "");

        assertEq(orderGateway.getOrdersCount(), 0);

        // check taker margin
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 1000 ether, positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );

        // check funding account
        assertEq(vault.getFund(taker), 0);
    }

    // NOTE: order gateway will not deposit / withdraw for user anymore
    function test_ExecuteOrderWithIncreasePositionShouldNotWithdrawCollateralForUser() public {
        config.setOrderDelaySeconds(0);

        _deposit(marketId, taker, 1000e6);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(config.owner());
        config.setOrderDelaySeconds(60);

        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 0.2 ether,
                oppositeAmountBound: 20 ether,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderExecuted(0, taker, marketId, keeper, abi.encode(delayedOrder));

        vm.prank(keeper);
        orderGateway.executeOrder(0, "");

        assertEq(orderGateway.getOrdersCount(), 0);

        // check taker margin
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 1000e18, positionSize: 1.2e18, openNotional: -1.2 * 100 * 1e18, unsettledPnl: 0 })
        );

        // check collateral transfer
        assertEq(collateralToken.balanceOf(taker), 0);
    }

    // NOTE: order gateway will not deposit / withdraw for user anymore
    function test_ExecuteOrderWithReversePositionShouldNotWithdrawCollateralForUser() public {
        config.setOrderDelaySeconds(0);

        _deposit(marketId, taker, 1000e6);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(config.owner());
        config.setOrderDelaySeconds(60);

        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1.2 ether,
                oppositeAmountBound: 120 ether,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderExecuted(0, taker, marketId, keeper, abi.encode(delayedOrder));

        vm.prank(keeper);
        orderGateway.executeOrder(0, "");

        assertEq(orderGateway.getOrdersCount(), 0);

        // check taker margin
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 1000e18, positionSize: -0.2e18, openNotional: 0.2 * 100 * 1e18, unsettledPnl: 0 })
        );

        // check collateral transfer
        assertEq(collateralToken.balanceOf(taker), 0);
    }

    /// purge order

    function test_PurgeOrderIfDeadlineExceeded() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.startPrank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.stopPrank();

        skip(150);
        _mockPythPrice(100, 0, block.timestamp);

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderPurged(
            0,
            taker,
            marketId,
            keeper,
            abi.encode(delayedOrder),
            abi.encodeWithSelector(LibError.DeadlineExceeded.selector)
        );
        orderGateway.executeOrder(0, "");
    }

    function test_PurgeOrderIfInvalidMaker() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.startPrank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.stopPrank();

        // unregister maker, we don't provide unregister maker yet.
        // mock contract call here
        vm.mockCall(
            address(config),
            abi.encodeWithSelector(Config.isWhitelistedMaker.selector, marketId, address(maker)),
            abi.encode(false)
        );

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        // when it's a whitelisted maker, it does not need sender's permission to settle. but if it's not registered,
        // then sender needs maker's permission to settle, so now it's a AuthorizerNotAllow error
        vm.prank(keeper);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderPurged(
            0,
            taker,
            marketId,
            keeper,
            abi.encode(delayedOrder),
            abi.encodeWithSelector(LibError.AuthorizerNotAllow.selector, address(maker), address(orderGateway))
        );
        orderGateway.executeOrder(0, "");
    }

    function test_PurgeOrderIfInsufficientOutputAmount() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 150,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.startPrank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.stopPrank();

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderPurged(
            0,
            taker,
            marketId,
            keeper,
            abi.encode(delayedOrder),
            abi.encodeWithSelector(LibError.InsufficientOutputAmount.selector, 100, 150)
        );
        orderGateway.executeOrder(0, "");
    }

    function test_PurgeOrderIfExcessiveInputAmount() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1,
                oppositeAmountBound: 90,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.startPrank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.stopPrank();

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        vm.prank(keeper);
        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderPurged(
            0,
            taker,
            marketId,
            keeper,
            abi.encode(delayedOrder),
            abi.encodeWithSelector(LibError.ExcessiveInputAmount.selector, 100, 90)
        );
        orderGateway.executeOrder(0, "");
    }

    function test_PurgeOrderIfNotEnoughFreeCollateral() public {
        // open position with exceeded leverage
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100e18,
                oppositeAmountBound: 10000e18,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.startPrank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.stopPrank();

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderPurged(
            0,
            taker,
            marketId,
            keeper,
            abi.encode(delayedOrder),
            abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker)
        );

        vm.prank(keeper);
        orderGateway.executeOrder(0, "");
    }

    function test_PurgeOrderIfZeroAmount() public {
        // open position with exceeded leverage
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 0,
                oppositeAmountBound: 0,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.startPrank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.stopPrank();

        skip(100);
        _mockPythPrice(100, 0, block.timestamp);

        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderPurged(
            0,
            taker,
            marketId,
            keeper,
            abi.encode(delayedOrder),
            abi.encodeWithSelector(LibError.ZeroAmount.selector)
        );

        vm.prank(keeper);
        orderGateway.executeOrder(0, "");
    }

    function test_RevertIf_EarlyExecution() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        vm.prank(keeper);
        vm.expectRevert(LibError.OrderExecutedTooEarly.selector);
        orderGateway.executeOrder(0, "");
    }

    function test_RevertIf_UncatchedUnknowError() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        skip(100);
        _mockPythPrice(100, 0);

        vm.mockCallRevert(
            address(clearingHouse),
            abi.encodeWithSelector(ClearingHouse.openPositionFor.selector),
            "ClearingHouse: Unknown error" // mock clearingHouse error
        );

        vm.prank(keeper);
        vm.expectRevert("ClearingHouse: Unknown error");
        orderGateway.executeOrder(0, "");
    }

    function test_executeOrderBySelf_RevertIf_isInvalidSender() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        vm.prank(taker);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        OrderGateway.DelayedOrder memory delayedOrder = orderGateway.getOrder(0);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidSender.selector, keeper));
        orderGateway.executeOrderBySelf(delayedOrder, "");
    }
}
