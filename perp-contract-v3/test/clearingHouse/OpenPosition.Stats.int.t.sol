// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ClearingHouseIntSetup.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { TestMaker } from "../helper/TestMaker.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";

contract OpenPositionStatsInt is ClearingHouseIntSetup {
    TestMaker public maker;
    address public taker = makeAddr("taker");
    address public taker2 = makeAddr("taker2");

    function setUp() public override {
        super.setUp();

        maker = _newMarketWithTestMaker(marketId);
        maker.setBaseToQuotePrice(150e18);
        _mockPythPrice(150, 0);

        _deposit(marketId, address(maker), 10000e6);
        _deposit(marketId, taker, 1000e6);
        _deposit(marketId, taker2, 1000e6);
    }

    function test_TakerIncreaseLongPosition() public {
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 1500 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(longGlobal.totalOpenNotional, 1500 ether);
            assertEq(shortGlobal.totalOpenNotional, 0 ether);
        }

        // taker long 10 ether,
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 3000 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(longGlobal.totalOpenNotional, 3000 ether);
            assertEq(shortGlobal.totalOpenNotional, 0 ether);
        }
    }

    function test_TakerReduceLongPosition() public {
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 1500 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(longGlobal.totalOpenNotional, 1500 ether);
            assertEq(shortGlobal.totalOpenNotional, 0 ether);
        }

        // taker short 3 ether,
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 3 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 1050 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(longGlobal.totalOpenNotional, 1050 ether);
            assertEq(shortGlobal.totalOpenNotional, 0 ether);
        }
    }

    function test_TakerReverseLongPosition() public {
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 1500 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(longGlobal.totalOpenNotional, 1500 ether);
            assertEq(shortGlobal.totalOpenNotional, 0 ether);
        }

        // taker short 15 ether,
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 15 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 750 ether);
            assertEq(longGlobal.totalOpenNotional, 0 ether);
            assertEq(shortGlobal.totalOpenNotional, 750 ether);
        }
    }

    function test_TakerIncreaseShortPosition() public {
        // taker short 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 1500 ether);
            assertEq(longGlobal.totalOpenNotional, 0 ether);
            assertEq(shortGlobal.totalOpenNotional, 1500 ether);
        }

        // taker short 10 ether,
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 3000 ether);
            assertEq(longGlobal.totalOpenNotional, 0 ether);
            assertEq(shortGlobal.totalOpenNotional, 3000 ether);
        }
    }

    function test_TakerReduceShortPosition() public {
        // taker short 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 1500 ether);
            assertEq(longGlobal.totalOpenNotional, 0 ether);
            assertEq(shortGlobal.totalOpenNotional, 1500 ether);
        }

        // taker long 3 ether,
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 3 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 1050 ether);
            assertEq(longGlobal.totalOpenNotional, 0 ether);
            assertEq(shortGlobal.totalOpenNotional, 1050 ether);
        }
    }

    function test_TakerReverseShortPosition() public {
        // taker short 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 1500 ether);
            assertEq(longGlobal.totalOpenNotional, 0 ether);
            assertEq(shortGlobal.totalOpenNotional, 1500 ether);
        }

        // taker long 15 ether,
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 15 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        {
            (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
                .getUtilizationGlobal(0);
            assertEq(longGlobal.totalReceiverOpenNotional, 750 ether);
            assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
            assertEq(longGlobal.totalOpenNotional, 750 ether);
            assertEq(shortGlobal.totalOpenNotional, 0 ether);
        }
    }
}
