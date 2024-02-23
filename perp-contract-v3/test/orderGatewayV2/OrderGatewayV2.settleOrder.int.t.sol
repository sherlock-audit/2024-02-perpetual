// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./OrderGatewayV2IntSetup.sol";
import { OrderGatewayV2 } from "../../src/orderGatewayV2/OrderGatewayV2.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { TestMaker } from "../helper/TestMaker.sol";

// notion detail: https://www.notion.so/perp/Limit-Order-with-CLOB-fc215c94ce0b4a4da78fa74f22832f06?pvs=4#d8b26f6e80f7466288360a5f877240a7
contract OrderGatewayV2SettleOrderIntTest is OrderGatewayV2IntSetup {
    using FixedPointMathLib for int256;

    // T1xM1 (taker can be partial filled)
    function test_SettleOrderOpenPositionWhenMakerIsOpenPositionOrder() public {
        // taker order (short 1 eth)
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            99.5 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 0.5 eth)
        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            0.4 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(makerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -0.4 ether, openNotional: 40 ether, unsettledPnl: 0 }) // use maker price to settle
        );

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 0.4 ether, openNotional: -40 ether, unsettledPnl: 0 })
        );

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    // T1xM2 (taker can be partial filled)
    function test_SettleOrderOpenPositionWhenMakerIsFokOpenPositionOrder() public {
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            99.5 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 0.4 eth)
        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            0.4 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: address(makerOrderOwner),
            makerData: abi.encode(makerSignOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(makerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -0.4 ether, openNotional: 40 ether, unsettledPnl: 0 }) // use maker price to settle
        );

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 0.4 ether, openNotional: -40 ether, unsettledPnl: 0 })
        );

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    // T1xM3 (taker can be partial filled)
    function test_SettleOrderOpenPositionWhenMakerIsFokReduceOnlyOrder() public {
        // maker open (0.4 short) first, then close later
        _openPositionOnTestMaker(
            makerOrderOwner,
            makerOrderOwnerPk,
            -0.4 ether,
            0.4 ether,
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
            99.5 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 0.4 eth)
        OrderGatewayV2.SignedOrder memory makerClosePositionSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            0.4 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "makerClosePositionSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerClosePositionSignOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(
            makerClosePositionSignOrder.order,
            0.4 ether,
            makerClosePositionSignOrder.order.price,
            makerClosePositionSignOrder.order.owner
        );
        _expectEmitOrderFilled(
            takerSignOrder.order,
            0.4 ether,
            makerClosePositionSignOrder.order.price,
            makerClosePositionSignOrder.order.owner
        );
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -0.4 ether, openNotional: 40 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD + defaultRelayFee);

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerClosePositionSignOrder.order.owner,
            makerClosePositionSignOrder.order.id
        );
        assertEq(makerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(makerOrderOwner)), defaultMarginXCD * 2);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 3);
    }

    // T1xM4 (taker can be partial filled)
    function test_SettleOrderOpenPositionWhenMakerIsTestMaker() public {
        // taker open 1 ether long, but filled 0.4 ether
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 0.4 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        _expectEmitOrderFilled(takerSignedOrder.order, 0.4 ether, 100 ether, address(maker));
        orderGatewayV2.settleOrder(settleOrderParams);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 0.4 ether, openNotional: -40 ether, unsettledPnl: 0 })
        );
    }

    // T2xM1 (maker partial filled)
    function test_SettleOrderFokOpenPositionWhenMakerIsOpenPositionOrder() public {
        // taker order (short 1 eth)
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -0.4 ether,
            99.5 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 2 eth)
        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            2 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(makerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -0.4 ether, openNotional: 40 ether, unsettledPnl: 0 }) // use maker price to settle
        );

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 0.4 ether, openNotional: -40 ether, unsettledPnl: 0 })
        );

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    // T2xM2
    function test_SettleOrderFokOpenPositionWhenMakerIsFokOpenPositionOrder() public {
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            99.5 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 1 eth)
        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
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
        _expectEmitOrderFilled(makerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -1 ether, openNotional: 100 ether, unsettledPnl: 0 }) // use maker price to settle
        );

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 1 ether, openNotional: -100 ether, unsettledPnl: 0 })
        );

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    // T2xM3 (maker close fok)
    function test_SettleOrderFokOpenPositionWhenMakerIsFokReduceOnlyOrder() public {
        // maker open (1 short) first, then close later
        _openPositionOnTestMaker(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerOpenPositionSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            99.5 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 1 eth)
        OrderGatewayV2.SignedOrder memory makerClosePositionSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            1 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "makerClosePositionSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 1 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerClosePositionSignOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(
            makerClosePositionSignOrder.order,
            1 ether,
            makerClosePositionSignOrder.order.price,
            makerClosePositionSignOrder.order.owner
        );
        _expectEmitOrderFilled(
            takerSignOrder.order,
            1 ether,
            makerClosePositionSignOrder.order.price,
            makerClosePositionSignOrder.order.owner
        );
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -1 ether, openNotional: 100 ether, unsettledPnl: 0 }) // use maker price to settle
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD + defaultRelayFee);

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerClosePositionSignOrder.order.owner,
            makerClosePositionSignOrder.order.id
        );
        assertEq(makerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(makerOrderOwner)), defaultMarginXCD * 2);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 3);
    }

    // T2xM4
    function test_SettleOrderFokOpenPositionWhenMakerIsTestMaker() public {
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            99.5 ether,
            defaultMarginXCD,
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

        vm.startPrank(relay);
        _expectEmitOrderFilled(takerSignOrder.order, 1 ether, 100 ether, address(maker));
        orderGatewayV2.settleOrder(settleOrderParams);

        uint256 filledAmount = orderGatewayV2.getOrderFilledAmount(takerSignOrder.order.owner, takerSignOrder.order.id);
        assertEq(filledAmount, 1 ether);
        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -1 ether, openNotional: 100 ether, unsettledPnl: 0 })
        );
    }

    // T3xM1 (maker can be partial filled)
    function test_SettleOrderFokReduceOnlyWhenMakerIsOpenPositionOrder() public {
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
            1.4 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
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
        _expectEmitOrderFilled(makerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 }) // use maker price to settle
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD * 2);

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 1 ether, openNotional: -100 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(makerOrderOwner)), defaultMarginXCD + defaultRelayFee);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 3);
    }

    // (taker and maker can be partial filled)
    function test_SettleOrderPartialFillReduceOnlyWhenMakerIsOpenPositionOrder() public {
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
            -1 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerSignOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            1.4 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(makerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 0.4 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 60 ether, positionSize: 0.6 ether, openNotional: -60 ether, unsettledPnl: 0 }) // use maker price to settle
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD + 40e6);

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 0.4 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 0.4 ether, openNotional: -40 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(makerOrderOwner)), defaultMarginXCD + defaultRelayFee);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 3);
    }

    // T3xM2
    function test_SettleOrderFokReduceOnlyWhenMakerIsFokOpenPositionOrder() public {
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
            1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
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
        _expectEmitOrderFilled(makerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 }) // use maker price to settle
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD * 2);

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: 1 ether, openNotional: -100 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(makerOrderOwner)), defaultMarginXCD + defaultRelayFee);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 3);
    }

    // T3xM3
    function test_SettleOrderFokReduceOnlyWhenMakerIsFokReduceOnlyOrder() public {
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

        // maker short 1 eth first, then close later
        _openPositionOnTestMaker(
            makerOrderOwner,
            makerOrderOwnerPk,
            -1 ether,
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
            1 ether,
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
        _expectEmitOrderFilled(makerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        _expectEmitOrderFilled(takerSignOrder.order, 1 ether, makerSignOrder.order.price, makerSignOrder.order.owner);
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        uint256 takerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            takerSignOrder.order.owner,
            takerSignOrder.order.id
        );
        assertEq(takerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD * 2);

        // check maker
        uint256 makerFilledAmount = orderGatewayV2.getOrderFilledAmount(
            makerSignOrder.order.owner,
            makerSignOrder.order.id
        );
        assertEq(makerFilledAmount, 1 ether);
        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(makerOrderOwner)), defaultMarginXCD * 2);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 4);
    }

    // T3xM4
    function test_SettleOrderFokReduceOnlyWhenMakerIsTestMaker() public {
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

        OrderGatewayV2.SignedOrder memory takerCloseSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerCloseSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerCloseSignedOrder,
            fillAmount: 1 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        _expectEmitOrderFilled(takerCloseSignedOrder.order, 1 ether, 100 ether, address(maker));
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 0 ether, positionSize: 0 ether, openNotional: 0 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD * 2);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    function test_MatcherFeeShouldBeChargedOnlyAtFirstTimeFilled() public {
        uint256 orderGatewayUsdcBeforeSettle = vault.getFund(address(orderGatewayV2));

        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.startPrank(relay);
        orderGatewayV2.settleOrder(settleOrderParams);
        uint256 orderGatewayUsdcAfterSettle = vault.getFund(address(orderGatewayV2));
        assertEq(orderGatewayUsdcAfterSettle, orderGatewayUsdcBeforeSettle + defaultRelayFee);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.2 ether,
            maker: address(maker),
            makerData: ""
        });

        orderGatewayV2.settleOrder(settleOrderParams);
        uint256 orderGatewayUsdcAfterSecondSettle = vault.getFund(address(orderGatewayV2));
        assertEq(orderGatewayUsdcAfterSecondSettle, orderGatewayUsdcAfterSettle);
        vm.stopPrank();
    }

    function test_MarginShouldBeDepositedOnlyAtFirstTimeFilled() public {
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignOrder,
            fillAmount: 0.4 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.startPrank(relay);
        orderGatewayV2.settleOrder(settleOrderParams);
        orderGatewayV2.settleOrder(settleOrderParams);
        vm.stopPrank();

        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 100 ether, positionSize: -0.8 ether, openNotional: 80 ether, unsettledPnl: 0 })
        );
    }

    function test_SkipMarginCheckWhenMakerIsReducingPosition() public {
        _deposit(marketId, makerOrderOwner, defaultMarginXCD);
        vm.startPrank(makerOrderOwner);

        // maker long with 10x leverage, at price 100
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        vm.stopPrank();

        // price drops to 95, maker's margin ratio is 5.2%(below 10%)
        _mockPythPrice(95, 0);

        // taker
        OrderGatewayV2.SignedOrder memory takerSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            5 ether,
            95 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignedOrder"
        );

        OrderGatewayV2.SignedOrder memory makerSignedOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            -5 ether,
            95 ether,
            0, // don't deposit margin to trigger NotEnoughFreeCollateral
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "makerSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);
        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerSignedOrder,
            fillAmount: 5 ether,
            maker: makerOrderOwner,
            makerData: abi.encode(makerSignedOrder)
        });

        vm.prank(relay);
        orderGatewayV2.settleOrder(settleOrderParams);

        _assertEq(
            _getPosition(marketId, makerOrderOwner),
            PositionProfile({ margin: 75 ether, positionSize: 5 ether, openNotional: -500 ether, unsettledPnl: 0 })
        );
    }

    function test_SettleOrderFokReduceOnlyWhenPartialCloseTakerPosition() public {
        // taker long 1 eth first, then partially close later
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

        OrderGatewayV2.SignedOrder memory takerPartialCloseSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -0.42 ether,
            100 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerCloseSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerPartialCloseSignedOrder,
            fillAmount: 0.42 ether,
            maker: address(maker),
            makerData: ""
        });

        int256 originalMarginRatio = _getMarginProfile(0, takerOrderOwner, 100).marginRatio;

        vm.prank(relay);
        _expectEmitOrderFilled(takerPartialCloseSignedOrder.order, 0.42 ether, 100 ether, address(maker));
        orderGatewayV2.settleOrder(settleOrderParams);

        int256 afterMarginRatio = _getMarginProfile(0, takerOrderOwner, 100).marginRatio;

        // check taker
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 58 ether, positionSize: 0.58 ether, openNotional: -58 ether, unsettledPnl: 0 })
        );
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD + 42e6);
        assertEq(afterMarginRatio, originalMarginRatio);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    function test_SettleOrderFokReduceOnlyWhenMarginIsInsufficient() public {
        // taker long 1 eth first, then close later
        _openPositionOnTestMaker(
            takerOrderOwner,
            takerOrderOwnerPk,
            10 ether,
            10 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOpenPosition"
        );

        // mock oracle price
        _mockPythPrice(95, 0);
        maker.setBaseToQuotePrice(95e18);

        OrderGatewayV2.SignedOrder memory takerPartialCloseSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -4.2 ether,
            95 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerPartialCloseSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerPartialCloseSignedOrder,
            fillAmount: 4.2 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        _expectEmitOrderFilled(takerPartialCloseSignedOrder.order, 4.2 ether, 95 ether, address(maker));
        orderGatewayV2.settleOrder(settleOrderParams);

        // check taker (realizedPnl = 4.2 * -5 = -21, margin: 100 - 21 = 79)
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({ margin: 79 ether, positionSize: 5.8 ether, openNotional: -580 ether, unsettledPnl: 0 })
        );
        // margin will keep in vault because margin ratio less than imRatio after reduce position
        assertEq(vault.getFund(address(takerOrderOwner)), defaultMarginXCD);

        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 2);
    }

    function test_SettleOrderFokWithPriceIsMaxUint256() public {
        // taker long 1 eth
        OrderGatewayV2.SignedOrder memory takerOpenSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            1 ether,
            type(uint256).max,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOpenPosition"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerOpenSignedOrder,
            fillAmount: 1 ether,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        _expectEmitOrderFilled(takerOpenSignedOrder.order, 1 ether, 100 ether, address(maker));
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function test_SettleOrderWithSelf() public {
        _deposit(takerOrderOwner, defaultRelayFee);

        // taker long 5 eth first, then close later
        _openPositionOnTestMaker(
            takerOrderOwner,
            takerOrderOwnerPk,
            5 ether,
            5 ether,
            100 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerOpenPosition"
        );

        // mock oracle price
        _mockPythPrice(95, 0);
        // taker places long 10 ether at price 95
        OrderGatewayV2.SignedOrder memory takerLongSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            10 ether,
            95 ether,
            defaultMarginXCD,
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerLongSignedOrder"
        );

        // taker close long position with own limit order
        OrderGatewayV2.SignedOrder memory takerCloseSignedOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -5 ether,
            95 ether,
            0,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.ReduceOnly,
            "takerCloseSignedOrder"
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);
        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: takerCloseSignedOrder,
            fillAmount: 5 ether,
            maker: takerOrderOwner,
            makerData: abi.encode(takerLongSignedOrder)
        });

        vm.prank(relay);
        _expectEmitOrderFilled(
            takerLongSignedOrder.order,
            5 ether,
            takerLongSignedOrder.order.price,
            takerLongSignedOrder.order.owner
        );
        _expectEmitOrderFilled(
            takerCloseSignedOrder.order,
            5 ether,
            takerLongSignedOrder.order.price,
            takerLongSignedOrder.order.owner
        );

        orderGatewayV2.settleOrder(settleOrderParams);

        // Step1: taker long 5 eth
        //  openNotional: -500
        //  positionSize: 10 ether

        // Step2: taker places long 10 eth limit order at price 95

        // Step3: taker close 5 eth
        // taker's marginRatio: ((100)-25)/500 = 0.15
        // (1) settle maker, increase 5 eth:
        //      openNotional: -500+(-95*5) = -975
        //      positionSize: 10 eth
        //      unrealizedPnl: -25

        // (2) sette taker, close 5 eth (50%),
        //      realizedPnl: (-975*50%)+5*95= -12.5
        //      openNotional: (-975*50%) = -487.5
        //      positionSize: 5,
        //      unrealizedPnl: -12.5
        //      accountValue = (200-12.5)-12.5 = 175
        //      marginRatio: (187.5+(-12.5))/487.5 =0.358974
        //      freeCollateral = 175- 487.5*0.1 = 126.25

        // (3) withdraw margin due to position reduction
        //      expectedAccountValue = 0.15 * 487.5 = 73.125
        //      withdraw = 175-73.125 = 101.875
        //      margin = (200-12.5)-101.875 = 85.625

        _getPosition(marketId, takerOrderOwner);
        _assertEq(
            _getPosition(marketId, takerOrderOwner),
            PositionProfile({
                margin: 85.625 ether,
                positionSize: 5 ether,
                openNotional: -487.5 ether,
                unsettledPnl: 0
            })
        );

        // margin will keep in vault because margin ratio less than imRatio after reduce position
        assertEq(vault.getFund(address(takerOrderOwner)), 101.875e6);
        assertEq(vault.getFund(address(orderGatewayV2)), defaultRelayFee * 3);
    }

    // FIXME: We shouldn't allow this to happen
    // probably add price band in OrderGatewayV2 or ClearingHouse,
    // only allow order.price to be oracle price +- 10% when settling orders
    // See https://app.asana.com/0/1202133750666965/1206662770651731/f
    function test_SettleOrder_AtExtremePrice() public {
        // takerOrderOwner deposit fund = (100 + 0.5) * 2 = 201
        // makerOrderOwner deposit fund = (100 + 0.5) * 2 = 201

        _mockPythPrice(100, 0);

        // taker order (short 1 eth) at price 1 wei
        OrderGatewayV2.SignedOrder memory takerSignOrder = _createSignOrder(
            takerOrderOwner,
            takerOrderOwnerPk,
            -1 ether,
            1,
            defaultMarginXCD, // 100
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
            "takerSignOrder"
        );

        // maker order (long 1 eth) at price 1 wei
        OrderGatewayV2.SignedOrder memory makerSignOrder = _createSignOrder(
            makerOrderOwner,
            makerOrderOwnerPk,
            1 ether,
            1,
            defaultMarginXCD, // 100
            OrderGatewayV2.TradeType.PartialFill,
            OrderGatewayV2.ActionType.OpenPosition,
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
        orderGatewayV2.settleOrder(settleOrderParams);

        skip(60 * 60 * 24 * 365);

        maker.setBaseToQuotePrice(200 ether);
        _mockPythPrice(200, 0);

        vm.prank(makerOrderOwner);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }
}
