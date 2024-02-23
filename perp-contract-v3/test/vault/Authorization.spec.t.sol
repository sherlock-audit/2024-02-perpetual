// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ORDER_GATEWAY, ORDER_GATEWAY_V2 } from "../../src/addressResolver/LibAddressResolver.sol";

import { VaultSpecSetup } from "./VaultSpecSetup.sol";

contract VaultAuthorizationSpec is VaultSpecSetup {
    address public mockedOrderGateway = makeAddr("mockedOrderGateway");
    address public mockedOrderGatewayV2 = makeAddr("mockedOrderGatewayV2");
    address public trader = makeAddr("trader");
    address public trader2 = makeAddr("trader2");

    function setUp() public override {
        super.setUp();

        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, ORDER_GATEWAY),
            abi.encode(mockedOrderGateway)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, ORDER_GATEWAY_V2),
            abi.encode(mockedOrderGatewayV2)
        );
    }

    function test_setAuthorization() public {
        vm.startPrank(trader);
        vault.setAuthorization(mockedOrderGateway, true);
        vault.setAuthorization(mockedOrderGatewayV2, true);
        vm.stopPrank();

        assertEq(vault.isAuthorized(trader, mockedOrderGateway), true);
        assertEq(vault.isAuthorized(trader, mockedOrderGatewayV2), true);
    }

    function test_setAuthorization_RevertIf_NotWhitelistedAuthorization() public {
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotWhitelistedAuthorization.selector));
        vault.setAuthorization(trader2, true);
    }
}
