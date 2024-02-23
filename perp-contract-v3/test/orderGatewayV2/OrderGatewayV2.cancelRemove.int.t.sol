// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { OrderGatewayV2IntSetup } from "./OrderGatewayV2IntSetup.sol";
import { OrderGatewayV2 } from "../../src/orderGatewayV2/OrderGatewayV2.sol";
import { LibError } from "../../src/common/LibError.sol";
import { TestMaker } from "../helper/TestMaker.sol";

contract OrderGatewayV2CancelRemove is OrderGatewayV2IntSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_cancelOrderByOrderOwner() public {
        // create order
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("takerSignedOrder")
        );

        // cancel order
        vm.prank(takerOrderOwner);
        orderGatewayV2.cancelOrder(takerSignedOrder);

        assertEq(orderGatewayV2.isOrderCanceled(takerSignedOrder.order.owner, takerSignedOrder.order.id), true);
    }

    function test_cancelOrderByNotOrderOwner() public {
        // create order
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("takerSignedOrder")
        );

        // cancel order
        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        orderGatewayV2.cancelOrder(takerSignedOrder);

        assertEq(orderGatewayV2.isOrderCanceled(takerSignedOrder.order.owner, takerSignedOrder.order.id), false);
    }

    function test_takerCanceledOrderCannotBeSettled() public {
        // create order
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("takerSignedOrder")
        );

        // cancel order
        vm.prank(takerOrderOwner);
        vm.expectEmit(true, true, true, true, address(orderGatewayV2));
        emit OrderGatewayV2.OrderCanceled(takerSignedOrder.order.owner, takerSignedOrder.order.id, "Canceled");
        orderGatewayV2.cancelOrder(takerSignedOrder);

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderWasCanceled.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_makerCanceledOrderCannotBeSettled() public {
        // create order
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("takerSignedOrder")
        );

        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("makerSignedOrder")
        );

        // cancel order
        vm.prank(makerOrderOwner);
        vm.expectEmit(true, true, true, true, address(orderGatewayV2));
        emit OrderGatewayV2.OrderCanceled(makerSignedOrder.order.owner, makerSignedOrder.order.id, "Canceled");
        orderGatewayV2.cancelOrder(makerSignedOrder);

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderWasCanceled.selector,
                makerSignedOrder.order.owner,
                makerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }
}
