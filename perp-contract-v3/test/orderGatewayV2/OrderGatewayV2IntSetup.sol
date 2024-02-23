// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../clearingHouse/ClearingHouseIntSetup.sol";
import { OrderGatewayV2 } from "../../src/orderGatewayV2/OrderGatewayV2.sol";
import { UniversalSigValidator } from "../../src/external/universalSigValidator/UniversalSigValidator.sol";
import { TestMaker } from "../helper/TestMaker.sol";

contract OrderGatewayV2IntSetup is ClearingHouseIntSetup {
    OrderGatewayV2 public orderGatewayV2;
    TestMaker maker;
    address relay = makeAddr("relay");
    address public takerOrderOwner;
    uint256 public takerOrderOwnerPk;
    address public makerOrderOwner;
    uint256 public makerOrderOwnerPk;
    uint256 public defaultMarginXCD = 100e6;
    uint256 public defaultRelayFee = 0.5e6;

    function setUp() public virtual override {
        super.setUp();

        // deploy contract
        UniversalSigValidator universalSigValidator = new UniversalSigValidator();
        addressManager.setAddress(UNIVERSAL_SIG_VALIDATOR, address(universalSigValidator));
        orderGatewayV2 = new OrderGatewayV2();
        _enableInitialize(address(orderGatewayV2));
        orderGatewayV2.initialize("OrderGatewayV2", "1", address(addressManager));
        orderGatewayV2.setRelayer(relay, true);
        addressManager.setAddress(ORDER_GATEWAY_V2, address(orderGatewayV2));
        config.setMaxRelayFee(defaultRelayFee);

        // prepare maker
        maker = _newMarketWithTestMaker(marketId);
        _deposit(marketId, address(maker), 10000e6);
        maker.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);

        // prepare taker order & maker order
        (takerOrderOwner, takerOrderOwnerPk) = makeAddrAndKey("takerOrderOwner");
        (makerOrderOwner, makerOrderOwnerPk) = makeAddrAndKey("makerOrderOwner");
        vm.startPrank(takerOrderOwner);
        clearingHouse.setAuthorization(address(orderGatewayV2), true);
        vault.setAuthorization(address(orderGatewayV2), true);
        vm.stopPrank();
        vm.startPrank(makerOrderOwner);
        clearingHouse.setAuthorization(address(orderGatewayV2), true);
        vault.setAuthorization(address(orderGatewayV2), true);
        vm.stopPrank();
        _deposit(takerOrderOwner, (defaultMarginXCD + defaultRelayFee) * 2);
        _deposit(makerOrderOwner, (defaultMarginXCD + defaultRelayFee) * 2);
    }

    function test_excludeFromCoverageReport() public virtual override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function _openPositionOnTestMaker(
        address orderOwner,
        uint256 orderOwnerPk,
        int256 amount,
        uint256 fillAmount,
        uint256 price,
        uint256 marginXCD,
        OrderGatewayV2.TradeType tradeType,
        OrderGatewayV2.ActionType action,
        bytes memory id
    ) internal {
        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            orderOwner,
            orderOwnerPk,
            amount,
            price,
            marginXCD,
            tradeType,
            action,
            id
        );

        OrderGatewayV2.SettleOrderParam[] memory settleOrderParams = new OrderGatewayV2.SettleOrderParam[](1);

        settleOrderParams[0] = OrderGatewayV2.SettleOrderParam({
            signedOrder: signedOrder,
            fillAmount: fillAmount,
            maker: address(maker),
            makerData: ""
        });

        vm.prank(relay);
        orderGatewayV2.settleOrder(settleOrderParams);
    }

    function _createSignOrder(
        address orderOwner,
        uint256 orderOwnerPk,
        int256 amount,
        uint256 price,
        uint256 marginXCD,
        OrderGatewayV2.TradeType tradeType,
        OrderGatewayV2.ActionType action,
        bytes memory id
    ) internal view returns (OrderGatewayV2.SignedOrder memory) {
        OrderGatewayV2.Order memory order = OrderGatewayV2.Order({
            action: action,
            marketId: marketId,
            amount: amount,
            price: price,
            expiry: block.timestamp,
            tradeType: tradeType,
            owner: orderOwner,
            marginXCD: marginXCD,
            relayFee: defaultRelayFee,
            id: keccak256(id)
        });

        OrderGatewayV2.SignedOrder memory signedOrder = OrderGatewayV2.SignedOrder({
            order: order,
            signature: _signOrder(orderOwnerPk, order)
        });

        return signedOrder;
    }

    function _signOrder(uint256 pk, OrderGatewayV2.Order memory order) internal view returns (bytes memory signature) {
        bytes32 hash = orderGatewayV2.getOrderHash(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        return abi.encodePacked(r, s, v);
    }

    function _expectEmitOrderFilled(
        OrderGatewayV2.Order memory order,
        uint256 fillAmount,
        uint256 filledPrice,
        address expectedMaker
    ) internal {
        vm.expectEmit(true, true, true, true, address(orderGatewayV2));
        emit OrderGatewayV2.OrderFilled(
            order.owner,
            order.id,
            order.action,
            order.tradeType,
            order.marketId,
            order.amount,
            fillAmount,
            order.price,
            filledPrice,
            order.expiry,
            order.marginXCD,
            order.relayFee,
            expectedMaker
        );
    }
}
