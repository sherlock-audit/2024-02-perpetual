// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { OrderGatewayV2IntSetup } from "./OrderGatewayV2IntSetup.sol";
import { OrderGatewayV2 } from "../../src/orderGatewayV2/OrderGatewayV2.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { LibError } from "../../src/common/LibError.sol";
import { TestMaker } from "../helper/TestMaker.sol";

// notion detail: https://www.notion.so/perp/Limit-Order-with-CLOB-fc215c94ce0b4a4da78fa74f22832f06?pvs=4#d8b26f6e80f7466288360a5f877240a7
contract OrderGatewayV2SettleOrderRevertIntTest is OrderGatewayV2IntSetup {
    using FixedPointMathLib for int256;

    function setUp() public override {
        super.setUp();
    }

    function test_RevertIf_FillAmountNotEqFokOrderAmount() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 2 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.UnableToFillFok.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 0.4 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.UnableToFillFok.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_FillAmountGtTakerOrderRemainingAmount() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory firstSettleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);
        OrderGatewayV2.SettleOrderParam[] memory secondSettleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        firstSettleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 0.7 ether,
            maker: address(maker),
            makerData: ""
        });

        secondSettleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 0.4 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.startPrank(relay);
        orderGatewayV2.settleOrder(firstSettleOrderParams);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.ExceedOrderAmount.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id,
                0.7 ether
            )
        );
        orderGatewayV2.settleOrder(secondSettleOrderParams);
        vm.stopPrank();
    }

    function test_RevertIf_OrderHasExpired() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.warp(10);

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderHasExpired.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_WrongSig() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOrder"
        );
        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

        // replace takerSignedOrder's signature with makerSignedOrder's signature
        takerSignedOrder.signature = makerSignedOrder.signature;
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
                LibError.OrderSignatureOwnerError.selector,
                takerOrderOwner,
                takerSignedOrder.order.id,
                "Invalid signature"
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_TakerOrderHasSameSideWithMakerOrder() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

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
                LibError.OrderSideMismatched.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id,
                makerSignedOrder.order.owner,
                makerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_TakerOrderHasDifferentMarketWithMakerOrder() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        // change marketId
        marketId = 2;
        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

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
                LibError.OrderMarketMismatched.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id,
                0,
                makerSignedOrder.order.owner,
                makerSignedOrder.order.id,
                2
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_TakerOrderCanNotBeFulfilledWithMakerPrice() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            110 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        vm.prank(relay);
        vm.expectRevert(abi.encodeWithSelector(LibError.ExcessiveInputAmount.selector, 110 ether, 100 ether));
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_FillAmountGtReduceOnlySize() public {
        _openPositionOnTestMaker(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory takerClosePositionSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerClosePositionSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerClosePositionSignedOrder,
            fillAmount: 1.4 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.UnableToFillFok.selector,
                takerClosePositionSignedOrder.order.owner,
                takerClosePositionSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_MakerOrderHasExpired() public {
        OrderGatewayV2.Order memory takerOrder = OrderGatewayV2.Order({
            action: OrderGatewayV2.ActionType.OpenPosition,
            marketId: marketId,
            amount: 1 ether,
            price: 100 ether,
            expiry: block.timestamp + 100,
            tradeType: OrderGatewayV2.TradeType.FoK,
            owner: takerOrderOwner,
            marginXCD: defaultMarginXCD,
            relayFee: defaultRelayFee,
            id: keccak256("takerOrder")
        });

        OrderGatewayV2.SignedOrder memory takerSignedOrder = OrderGatewayV2.SignedOrder({
            order: takerOrder,
            signature: _signOrder(takerOrderOwnerPk, takerOrder)
        });

        OrderGatewayV2.Order memory makerOrder = OrderGatewayV2.Order({
            action: OrderGatewayV2.ActionType.OpenPosition,
            marketId: marketId,
            amount: -1 ether,
            price: 100 ether,
            expiry: block.timestamp,
            tradeType: OrderGatewayV2.TradeType.FoK,
            owner: makerOrderOwner,
            marginXCD: defaultMarginXCD,
            relayFee: defaultRelayFee,
            id: keccak256("makerOrder")
        });

        OrderGatewayV2.SignedOrder memory makerSignedOrder = OrderGatewayV2.SignedOrder({
            order: makerOrder,
            signature: _signOrder(makerOrderOwnerPk, makerOrder)
        });

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);
        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        vm.warp(10);

        vm.prank(relay);
        vm.expectRevert(abi.encodeWithSelector(LibError.OrderHasExpired.selector, makerOrder.owner, makerOrder.id));
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_FillAmountNotEqFokMakerOrderAmount() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -0.4 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);
        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        // ask to fill 1 but maker order only has 0.4
        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.UnableToFillFok.selector,
                makerSignedOrder.order.owner,
                makerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 0.2 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        // ask to fill 0.2 but taker order has 0.4 FoK
        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.UnableToFillFok.selector,
                takerSignedOrder.order.owner,
                takerSignedOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_MakerNotEnoughFreeCollateral() public {
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            100 ether,
            0, // don't deposit margin to trigger NotEnoughFreeCollateral
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);
        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        vm.prank(relay);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, makerOrderOwner));
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertI_SettlingTwoFokReduceOnlyOrdersWithSameDirection() public {
        // taker long 1 eth first, then close later
        _openPositionOnTestMaker(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOpenPosition"
        );

        // maker long 1 eth first, then close later
        _openPositionOnTestMaker(
            makerOrderOwner,
            makerOrderOwnerPk,
            1 ether,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerOpenPosition"
        );

        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerSignOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "makerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignOrder)
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderSideMismatched.selector,
                takerSignOrder.order.owner,
                takerSignOrder.order.id,
                makerSignOrder.order.owner,
                makerSignOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_SettleReduceOnlyOrderWhenSideMismatch() public {
        // taker long 1 eth first, then close later
        _openPositionOnTestMaker(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOpenPosition"
        );

        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 1 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.ReduceOnlySideMismatch.selector,
                takerSignOrder.order.owner,
                takerSignOrder.order.id,
                takerSignOrder.order.amount,
                1 ether
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_SettleReduceOnlyOrderWhenAmountExceedPositionSize() public {
        // taker long 1 eth first, then close later
        _openPositionOnTestMaker(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOpenPosition"
        );

        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1.2 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 1.2 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.UnableToReduceOnly.selector,
                takerSignOrder.order.owner,
                takerSignOrder.order.id,
                takerSignOrder.order.amount.abs(),
                1 ether
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_RevertIf_SettleOrderWhenTakerOrderAmountIsZero() public {
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            0 ether,
            100 ether,
            100 ether,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 1 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderAmountZero.selector,
                takerSignOrder.order.owner,
                takerSignOrder.order.id
            )
        );
        orderGatewayV2.settleOrder(settleOrderParams);
    }
}
