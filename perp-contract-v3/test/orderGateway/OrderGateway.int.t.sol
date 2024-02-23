// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./OrderGatewayIntSetup.sol";
import { OrderGateway } from "../../src/orderGateway/OrderGateway.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { TestMaker } from "../helper/TestMaker.sol";

contract OrderGatewayInt is OrderGatewayIntSetup {
    address taker1 = makeAddr("taker1");
    address taker2 = makeAddr("taker2");
    uint256 defaultMargin = 100e6;

    function setUp() public virtual override {
        super.setUp();
        _deposit(marketId, address(maker), 10000e6);
        maker.setBaseToQuotePrice(100e18);

        _mockPythPrice(100, 0);

        deal(address(collateralToken), taker1, defaultMargin);
        deal(taker1, 10 ether);
        vm.startPrank(taker1);
        clearingHouse.setAuthorization(address(orderGateway), true);
        vault.setAuthorization(address(orderGateway), true);
        vm.stopPrank();
    }

    function test_CreateOrder() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        OrderGateway.DelayedOrder memory expectedDelayedOrder = OrderGateway.DelayedOrder({
            orderType: OrderGateway.DelayedOrderType.OpenPosition,
            marketId: marketId,
            sender: taker1,
            data: data,
            createdAt: block.timestamp,
            executableAt: block.timestamp + 60
        });

        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderCreated(0, taker1, marketId, abi.encode(expectedDelayedOrder));
        vm.prank(taker1);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        assertEq(orderGateway.getOrdersCount(), 1);
        assertEq(orderGateway.getUserOrdersCount(taker1), 1);

        uint[] memory ids = new uint[](1);
        ids[0] = 0;
        assertEq(orderGateway.getOrderIds(0, 1), ids);
        assertEq(orderGateway.getOrderIds(0, 10), ids);
        assertEq(orderGateway.getUserOrderIds(taker1, 0, 1), ids);
        assertEq(orderGateway.getUserOrderIds(taker1, 0, 10), ids);
        assertEq(orderGateway.getCurrentNonce(), 1);

        _assertEq(orderGateway.getOrder(0), expectedDelayedOrder);
    }

    function test_CreateOrderWithWithdraw() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        OrderGateway.DelayedOrder memory expectedDelayedOrder = OrderGateway.DelayedOrder({
            orderType: OrderGateway.DelayedOrderType.OpenPosition,
            marketId: marketId,
            sender: taker1,
            data: data,
            createdAt: block.timestamp,
            executableAt: block.timestamp + 60
        });

        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderCreated(0, taker1, marketId, abi.encode(expectedDelayedOrder));
        vm.prank(taker1);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        assertEq(orderGateway.getOrdersCount(), 1);
        assertEq(orderGateway.getUserOrdersCount(taker1), 1);

        uint[] memory ids = new uint[](1);
        ids[0] = 0;
        assertEq(orderGateway.getOrderIds(0, 1), ids);
        assertEq(orderGateway.getOrderIds(0, 10), ids);
        assertEq(orderGateway.getUserOrderIds(taker1, 0, 1), ids);
        assertEq(orderGateway.getUserOrderIds(taker1, 0, 10), ids);
        assertEq(orderGateway.getCurrentNonce(), 1);

        _assertEq(orderGateway.getOrder(0), expectedDelayedOrder);
    }

    function test_CancelOrder() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            }),
            0
        );

        // create 2 orders
        vm.startPrank(taker1);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
        vm.stopPrank();

        assertEq(orderGateway.getOrdersCount(), 2);
        assertEq(orderGateway.getUserOrdersCount(taker1), 2);

        vm.expectEmit(true, true, true, true, address(orderGateway));
        emit OrderGateway.OrderCanceled(0);
        vm.prank(taker1);
        orderGateway.cancelOrder(0);

        assertEq(orderGateway.getOrdersCount(), 1);
        assertEq(orderGateway.getUserOrdersCount(taker1), 1);
    }

    function test_CancelOrder_RevertIf_OrderNotExisted() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.OrderNotExisted.selector, 0));
        orderGateway.cancelOrder(0);
    }

    function test_CancelOrder_RevertIf_CancelOthersOrder() public {
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );

        // taker1 create 2 orders
        vm.prank(taker1);
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        // taker2 can't cancel taker1's order
        vm.expectRevert(abi.encodeWithSelector(LibError.OrderNotExisted.selector, 0));
        vm.prank(taker2);
        orderGateway.cancelOrder(0);
    }

    function test_CreateOrder_RevertIf_BadData() public {
        bytes memory badData = "bad data";
        vm.prank(taker1);
        vm.expectRevert(); // revert without reason string (fail to abi.decode))
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, badData);
    }

    function test_CreateOrder_RevertIf_InvalidDeadline() public {
        vm.prank(taker1);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidDeadline.selector, type(uint256).max));
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: type(uint256).max,
                makerData: ""
            })
        );
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);

        vm.warp(10000);

        vm.prank(taker1);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidDeadline.selector, block.timestamp - 1));
        bytes memory data2 = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp - 1,
                makerData: ""
            })
        );
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data2);
    }

    function test_CreateOrder_RevertIf_InvalidMaker() public {
        address invalidMaker = makeAddr("invalidMaker");
        vm.prank(taker1);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidMaker.selector, marketId, invalidMaker));
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: invalidMaker,
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
    }

    function test_CreateOrder_RevertIf_InvalidMarketId() public {
        vm.prank(taker1);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidMaker.selector, marketId + 10, address(maker)));
        bytes memory data = abi.encode(
            IClearingHouse.OpenPositionParams({
                marketId: marketId + 10,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1,
                oppositeAmountBound: 100,
                deadline: block.timestamp + 120,
                makerData: ""
            })
        );
        orderGateway.createOrder(OrderGateway.DelayedOrderType.OpenPosition, data);
    }
}
