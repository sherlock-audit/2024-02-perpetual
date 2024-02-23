// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { OrderGatewayV2 } from "./OrderGatewayV2.sol";

library LibOrder {
    //
    // INTERNAL
    //

    function getKey(OrderGatewayV2.Order memory order) internal pure returns (bytes32) {
        return getOrderKey(order.owner, order.id);
    }

    function getOrderKey(address owner, bytes32 id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, id));
    }
}
