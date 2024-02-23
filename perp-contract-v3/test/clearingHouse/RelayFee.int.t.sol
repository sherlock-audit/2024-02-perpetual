// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ClearingHouseIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract RelayFeeInt is ClearingHouseIntSetup {
    address public taker = makeAddr("taker");
    address public maker = makeAddr("maker");
    address public relayer = makeAddr("relayer");
    TestMaker public makerWithCallback;
    uint256 public maxRelayFee = 1e6;

    function setUp() public override {
        super.setUp();
        makerWithCallback = _newMarketWithTestMaker(marketId);
        _mockPythPrice(100, 0);

        // prepare relayer
        vm.mockCall(
            address(addressManager),
            abi.encodeWithSelector(AddressManager.getAddress.selector, "OrderGatewayV2"),
            abi.encode(relayer)
        );
        config.setMaxRelayFee(maxRelayFee);
        vm.prank(taker);
        clearingHouse.setAuthorization(relayer, true);
        vm.prank(maker);
        clearingHouse.setAuthorization(relayer, true);

        // prepare money
        _deposit(taker, 100e6);
        _deposit(maker, 100e6);
        _deposit(address(makerWithCallback), 100e6);
        _deposit(marketId, taker, 100e6);
        _deposit(marketId, maker, 100e6);
        _deposit(marketId, address(makerWithCallback), 100e6);
    }

    function _longWithRelayFee(uint256 takerRelayFee, uint256 makerRelayFee) private {
        _openPositionFor(marketId, taker, maker, 1 ether, 100, relayer, takerRelayFee, makerRelayFee);
    }

    function test_OpenPositionFor_TakerPayRelayFee() public {
        uint256 relayerFundBefore = vault.getFund(relayer);
        uint256 takerFundBefore = vault.getFund(taker);
        _openPositionFor(marketId, taker, maker, 1 ether, 100, relayer, maxRelayFee, 0);
        uint256 relayerFundAfter = vault.getFund(relayer);
        uint256 takerFundAfter = vault.getFund(taker);
        assertEq(relayerFundBefore + maxRelayFee, relayerFundAfter);
        assertEq(takerFundBefore - maxRelayFee, takerFundAfter);
    }

    function test_OpenPositionFor_RevertIfTakerRelayFeeTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(LibError.ExcessiveRelayFee.selector, taker, relayer, maxRelayFee + 1, maxRelayFee)
        );
        _openPositionFor(marketId, taker, maker, 1 ether, 100, relayer, maxRelayFee + 1, 0);
    }

    function test_OpenPositionFor_MakerPayRelayFee() public {
        uint256 relayerFundBefore = vault.getFund(relayer);
        uint256 makerFundBefore = vault.getFund(maker);
        _openPositionFor(marketId, taker, maker, 1 ether, 100, relayer, 0, maxRelayFee);
        uint256 relayerFundAfter = vault.getFund(relayer);
        uint256 makerFundAfter = vault.getFund(maker);
        assertEq(relayerFundBefore + maxRelayFee, relayerFundAfter);
        assertEq(makerFundBefore - maxRelayFee, makerFundAfter);
    }

    function test_OpenPositionFor_RevertIfMakerRelayFeeTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(LibError.ExcessiveRelayFee.selector, maker, relayer, maxRelayFee + 1, maxRelayFee)
        );
        _openPositionFor(marketId, taker, maker, 1 ether, 100, relayer, 0, maxRelayFee + 1);
    }

    function test_OpenPositionFor_RevertIf_HasMakerRelayFeeButMakerNotAuthRelayer() public {
        // taker set authorization for clearingHouse
        vm.expectRevert(
            abi.encodeWithSelector(LibError.AuthorizerNotAllow.selector, address(makerWithCallback), relayer)
        );
        vm.prank(relayer);
        clearingHouse.openPositionFor(
            IClearingHouse.OpenPositionForParams({
                marketId: marketId,
                maker: address(makerWithCallback),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp,
                makerData: "",
                taker: taker,
                takerRelayFee: 0,
                makerRelayFee: maxRelayFee
            })
        );
    }

    function test_ClosePositionFor_TakerPayRelayFee() public {
        _trade(taker, maker, 1 ether, 100);
        uint256 relayerFundBefore = vault.getFund(relayer);
        uint256 takerFundBefore = vault.getFund(taker);
        // close pos for + taker relayerFee
        vm.prank(relayer);
        clearingHouse.closePositionFor(
            IClearingHouse.ClosePositionForParams({
                marketId: marketId,
                maker: maker,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: abi.encode(IClearingHouse.MakerOrder({ amount: 100 ether })),
                taker: taker,
                takerRelayFee: maxRelayFee,
                makerRelayFee: 0
            })
        );
        uint256 relayerFundAfter = vault.getFund(relayer);
        uint256 takerFundAfter = vault.getFund(taker);
        assertEq(relayerFundBefore + maxRelayFee, relayerFundAfter);
        assertEq(takerFundBefore - maxRelayFee, takerFundAfter);
    }

    function test_ClosePositionFor_MakerPayRelayFee() public {
        _trade(taker, maker, 1 ether, 100);
        uint256 relayerFundBefore = vault.getFund(relayer);
        uint256 makerFundBefore = vault.getFund(maker);
        // close pos for + maker relayerFee
        vm.prank(relayer);
        clearingHouse.closePositionFor(
            IClearingHouse.ClosePositionForParams({
                marketId: marketId,
                maker: maker,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: abi.encode(IClearingHouse.MakerOrder({ amount: 100 ether })),
                taker: taker,
                takerRelayFee: 0,
                makerRelayFee: maxRelayFee
            })
        );
        uint256 relayerFundAfter = vault.getFund(relayer);
        uint256 makerFundAfter = vault.getFund(maker);
        assertEq(relayerFundBefore + maxRelayFee, relayerFundAfter);
        assertEq(makerFundBefore - maxRelayFee, makerFundAfter);
    }
}
