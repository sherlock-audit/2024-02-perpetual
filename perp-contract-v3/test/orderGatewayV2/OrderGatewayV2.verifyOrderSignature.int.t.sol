// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { OrderGatewayV2 } from "../../src/orderGatewayV2/OrderGatewayV2.sol";

import { OrderGatewayV2IntSetup } from "./OrderGatewayV2IntSetup.sol";
import { TestERC1271Wallet, Create2Factory } from "../helper/TestERC1271Wallet.sol";
import { LibError } from "../../src/common/LibError.sol";

contract OrderGatewayV2VerifyOrderSignature is OrderGatewayV2IntSetup {
    address public walletOwner;
    uint256 public walletOwnerPk;
    address public wrongOwner;
    uint256 public wrongOwnerPk;

    // aka magicBytes
    bytes32 ERC6492_DETECTION_SUFFIX = 0x6492649264926492649264926492649264926492649264926492649264926492;

    function setUp() public override {
        super.setUp();

        (walletOwner, walletOwnerPk) = makeAddrAndKey("walletOwner");
        (wrongOwner, wrongOwnerPk) = makeAddrAndKey("wrongOwner");
    }

    function test_Erc712Signature() public {
        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            walletOwner,
            walletOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("orderId")
        );

        orderGatewayV2.verifyOrderSignature(signedOrder);
    }

    function test_Erc712Signature_RevertIf_InvalidSignature() public {
        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            walletOwner,
            wrongOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("orderId")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderSignatureOwnerError.selector,
                walletOwner,
                signedOrder.order.id,
                "Invalid signature"
            )
        );
        orderGatewayV2.verifyOrderSignature(signedOrder);
    }

    function test_Erc1271Signature() public {
        TestERC1271Wallet testERC1271Wallet = new TestERC1271Wallet(walletOwner);

        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            address(testERC1271Wallet), // instead of walletOwner
            walletOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("orderId")
        );

        // UniversalSigValidator will call TestERC1271Wallet.isValidSignature()
        // and TestERC1271Wallet will verify signature with its owner
        orderGatewayV2.verifyOrderSignature(signedOrder);
    }

    function test_Erc1271Signature_RevertIf_InvalidSignature() public {
        TestERC1271Wallet testERC1271Wallet = new TestERC1271Wallet(walletOwner);

        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            address(testERC1271Wallet), // instead of walletOwner
            wrongOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("orderId")
        );

        // UniversalSigValidator will call TestERC1271Wallet.isValidSignature()
        // and TestERC1271Wallet will verify signature with its owner
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderSignatureOwnerError.selector,
                address(testERC1271Wallet),
                signedOrder.order.id,
                "Invalid signature"
            )
        );
        orderGatewayV2.verifyOrderSignature(signedOrder);
    }

    function test_Erc6492Signature() public {
        bytes32 salt = "12345";
        Create2Factory create2Factory = new Create2Factory();
        bytes memory factoryCalldata = abi.encodeWithSelector(Create2Factory.deploy.selector, walletOwner, salt);
        address testERC1271Wallet = create2Factory.getAddress(salt, walletOwner);

        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            testERC1271Wallet, // instead of walletOwner
            walletOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("orderId")
        );

        // see https://eips.ethereum.org/EIPS/eip-6492#signer-side
        bytes memory erc6492Signature = abi.encodePacked(
            abi.encode(address(create2Factory), factoryCalldata, signedOrder.signature),
            ERC6492_DETECTION_SUFFIX // aka magicBytes
        );
        signedOrder.signature = erc6492Signature;

        assertEq(testERC1271Wallet.code.length, 0); // testERC1271Wallet is not deployed yet

        orderGatewayV2.verifyOrderSignature(signedOrder);
    }

    function test_Erc6492Signature_RevertIf_InvalidSignature() public {
        bytes32 salt = "12345";
        Create2Factory create2Factory = new Create2Factory();
        bytes memory factoryCalldata = abi.encodeWithSelector(Create2Factory.deploy.selector, walletOwner, salt);
        address testERC1271Wallet = create2Factory.getAddress(salt, walletOwner);

        OrderGatewayV2.SignedOrder memory signedOrder = _createSignOrder(
            testERC1271Wallet, // instead of walletOwner
            wrongOwnerPk,
            1 ether,
            100 ether,
            100e6,
            OrderGatewayV2.TradeType.FoK,
            OrderGatewayV2.ActionType.OpenPosition,
            abi.encodePacked("orderId")
        );

        // see https://eips.ethereum.org/EIPS/eip-6492#signer-side
        bytes memory erc6492Signature = abi.encodePacked(
            abi.encode(address(create2Factory), factoryCalldata, signedOrder.signature),
            ERC6492_DETECTION_SUFFIX // aka magicBytes
        );
        signedOrder.signature = erc6492Signature;

        assertEq(testERC1271Wallet.code.length, 0); // testERC1271Wallet is not deployed yet

        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.OrderSignatureOwnerError.selector,
                address(testERC1271Wallet),
                signedOrder.order.id,
                "Invalid signature"
            )
        );
        orderGatewayV2.verifyOrderSignature(signedOrder);
    }
}
