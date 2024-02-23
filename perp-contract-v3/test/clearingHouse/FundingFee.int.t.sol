// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { TestMaker } from "../helper/TestMaker.sol";
import "./ClearingHouseIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract FundingFeeInt is ClearingHouseIntSetup {
    TestMaker public maker;
    TestMaker public maker2;
    address public taker1 = makeAddr("taker1");
    address public taker2 = makeAddr("taker2");

    function setUp() public override {
        ClearingHouseIntSetup.setUp();

        // prepare 1 maker
        maker = _newMarketWithTestMaker(marketId);
        maker2 = _newMarketWithTestMaker(marketId);

        // set target borrowing fee rate = 0 to ignore borrowing fee
        config.setMaxBorrowingFeeRate(marketId, 0, 0);

        // set funding-related configs
        config.setFundingConfig(marketId, 0.005e18, 1.3e18, address(maker));

        _deposit(marketId, taker1, 1000e6);
        _deposit(marketId, taker2, 1000e6);

        // maker deposits 10000
        _deposit(marketId, address(maker), 10000e6);
        // maker.setTotalDepositedAmount(10000 ether);

        // maker2 deposits 10000
        _deposit(marketId, address(maker2), 10000e6);
        // maker2.setTotalDepositedAmount(10000 ether);

        // set price = 100
        maker.setBaseToQuotePrice(100e18);
        maker2.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);
    }

    function test_takerHasLongPosition_payFundingFee() public {
        // taker1 long 10 eth on maker1
        vm.prank(taker1);
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

        skip(100);

        // rate = -(0.005 * 1000^1.3) / (10000 / 1) = -0.003971641174 per second per dollar
        assertEq(fundingFee.getCurrentFundingRate(marketId), -0.003971641173621407e18);

        // maker receive funding fee
        // -0.003971641174 * 1000 * 100 = 397.1641174
        int256 makerPendingFundingFee = fundingFee.getPendingFee(marketId, address(maker));
        assertEq(makerPendingFundingFee, -397.1641173621407e18);
        assertEq(vault.getPendingMargin(marketId, address(maker)), 397.1641173621407e18);

        // taker pay funding fee
        // -0.003971641174 * -1000 * 100 = 397.1641174
        int256 taker1PendingFundingFee = fundingFee.getPendingFee(marketId, taker1);
        assertEq(taker1PendingFundingFee, 397.1641173621407e18);
        assertEq(vault.getPendingMargin(marketId, taker1), -397.1641173621407e18);

        // taker1 close position, settle funding fee into margin
        int256 taker1MarginWithoutPendingBefore = vault.getSettledMargin(marketId, taker1);
        int256 makerMarginWithoutPendingBefore = vault.getSettledMargin(marketId, address(maker));
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        int256 taker1MarginWithoutPendingAfter = vault.getSettledMargin(marketId, taker1);
        assertEq(taker1MarginWithoutPendingAfter - taker1MarginWithoutPendingBefore, -taker1PendingFundingFee);
        int256 makerMarginWithoutPendingAfter = vault.getSettledMargin(marketId, address(maker));
        assertEq(makerMarginWithoutPendingAfter - makerMarginWithoutPendingBefore, -makerPendingFundingFee);
    }

    function test_takerHasShortPosition_payFundingFee() public {
        // taker1 short 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(100);

        // rate = (0.005 * 1000^1.3) / (10000 / 1) = 0.003971641174 per second per dollar
        assertEq(fundingFee.getCurrentFundingRate(marketId), 0.003971641173621407e18);

        // maker receive funding fee
        // 0.003971641174 * -1000 * 100 = 397.1641174
        int256 makerPendingFundingFee = fundingFee.getPendingFee(marketId, address(maker));
        assertEq(makerPendingFundingFee, -397.1641173621407e18);
        assertEq(vault.getPendingMargin(marketId, address(maker)), 397.1641173621407e18);

        // taker pay funding fee
        // 0.003971641174 * 1000 * 100 = 397.1641174
        int256 taker1PendingFundingFee = fundingFee.getPendingFee(marketId, taker1);
        assertEq(taker1PendingFundingFee, 397.1641173621407e18);
        assertEq(vault.getPendingMargin(marketId, taker1), -397.1641173621407e18);

        // taker1 close position, settle funding fee into margin
        int256 taker1MarginWithoutPendingBefore = vault.getSettledMargin(marketId, taker1);
        int256 makerMarginWithoutPendingBefore = vault.getSettledMargin(marketId, address(maker));
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        int256 taker1MarginWithoutPendingAfter = vault.getSettledMargin(marketId, taker1);
        assertEq(taker1MarginWithoutPendingAfter - taker1MarginWithoutPendingBefore, -taker1PendingFundingFee);
        int256 makerMarginWithoutPendingAfter = vault.getSettledMargin(marketId, address(maker));
        assertEq(makerMarginWithoutPendingAfter - makerMarginWithoutPendingBefore, -makerPendingFundingFee);
    }

    function test_TwoTakersWithOppositeDirection() public {
        // taker1 short 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 long 5 eth on maker1
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 5 ether,
                oppositeAmountBound: 500 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(100);

        // rate = (0.005 * 500^1.3) / (10000 / 1) = 0.001612987530370539 per second per dollar
        assertEq(fundingFee.getCurrentFundingRate(marketId), 0.001612987530370539e18);

        // maker receive funding fee
        // 0.001612987530370539 * -500 * 100 = -80.6493765185
        int256 maker1PendingFundingFee = fundingFee.getPendingFee(marketId, address(maker));
        assertEq(maker1PendingFundingFee, -80.64937651852695e18);
        assertEq(vault.getPendingMargin(marketId, address(maker)), 80.64937651852695e18);

        // taker1 pay funding fee
        // 0.001612987530370539 * 1000 * 100 = 161.2987530371
        assertEq(fundingFee.getPendingFee(marketId, taker1), 161.2987530370539e18);
        assertEq(vault.getPendingMargin(marketId, taker1), -161.2987530370539e18);

        // taker2 receive funding fee
        // 0.001612987530370539 * -500 * 100 = -80.6493765185
        assertEq(fundingFee.getPendingFee(marketId, taker2), -80.64937651852695e18);
        assertEq(vault.getPendingMargin(marketId, taker2), 80.64937651852695e18);

        // total paid funding fee >= total received funding fee
        assertGe(
            fundingFee.getPendingFee(marketId, address(taker1)),
            -(fundingFee.getPendingFee(marketId, address(maker2)) + fundingFee.getPendingFee(marketId, address(taker2)))
        );

        // maker1 deposit 1000, settle funding fee on maker1
        int256 makerMarginWithoutPendingBefore = vault.getSettledMargin(marketId, address(maker));

        deal(address(collateralToken), address(maker), 1000e6, true);
        vm.startPrank(address(maker));
        vault.deposit(address(maker), 1000e6);
        vault.transferFundToMargin(marketId, 1000e6);

        int256 makerMarginWithoutPendingAfter = vault.getSettledMargin(marketId, address(maker));
        assertEq(makerMarginWithoutPendingAfter - makerMarginWithoutPendingBefore, -maker1PendingFundingFee + 1000e18);
    }

    function test_TwoTakersWithSameDirection() public {
        // taker1 short 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 short 5 eth on maker1
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 5 ether,
                oppositeAmountBound: 500 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(100);

        // rate = (0.005 * 1500^1.3) / (10000 / 1) = 0.006728041182245408 per second per dollar
        assertEq(fundingFee.getCurrentFundingRate(marketId), 0.006728041182245408e18);

        // maker receive funding fee
        // 0.006728041182245407 * -1500 * 100 = -1009.2061773368
        assertEq(fundingFee.getPendingFee(marketId, address(maker)), -1009.2061773368112e18);
        assertEq(vault.getPendingMargin(marketId, address(maker)), 1009.2061773368112e18);

        // taker1 pay funding fee
        // 0.006728041182245407 * 1000 * 100 = 672.8041182245
        assertEq(fundingFee.getPendingFee(marketId, taker1), 672.8041182245408e18);
        assertEq(vault.getPendingMargin(marketId, taker1), -672.8041182245408e18);

        // taker2 pay funding fee
        // 0.006728041182245407 * 500 * 100 = 336.4020591123
        assertEq(fundingFee.getPendingFee(marketId, taker2), 336.40205911227040e18);
        assertEq(vault.getPendingMargin(marketId, taker2), -336.40205911227040e18);

        // total paid funding fee >= total received funding fee
        assertGe(
            fundingFee.getPendingFee(marketId, address(taker1)) + fundingFee.getPendingFee(marketId, address(taker2)),
            -fundingFee.getPendingFee(marketId, address(maker))
        );
    }

    function test_TwoTakersWithTwoMakers() public {
        // taker1 short 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 long 5 eth on maker2
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 5 ether,
                oppositeAmountBound: 500 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(100);

        // rate = (0.005 * 1000^1.3) / (10000 / 1) = 0.003971641174 per second per dollar
        assertEq(fundingFee.getCurrentFundingRate(marketId), 0.003971641173621407e18);

        // maker1 receive funding fee
        // 0.003971641174 * -1000 * 100 = -397.1641174
        assertEq(fundingFee.getPendingFee(marketId, address(maker)), -397.1641173621407e18);
        assertEq(vault.getPendingMargin(marketId, address(maker)), 397.1641173621407e18);

        // maker2 pay funding fee
        // 0.003971641174 * 500 * 100 = 198.5820587
        assertEq(fundingFee.getPendingFee(marketId, address(maker2)), 198.58205868107035e18);
        assertEq(vault.getPendingMargin(marketId, address(maker2)), -198.58205868107035e18);

        // taker1 pay funding fee
        // 0.003971641174 * 1000 * 100 = 397.1641174
        assertEq(fundingFee.getPendingFee(marketId, taker1), 397.1641173621407e18);
        assertEq(vault.getPendingMargin(marketId, taker1), -397.1641173621407e18);

        // taker2 receive funding fee
        // 0.003971641174 * -500 * 100 = -198.5820587
        assertEq(fundingFee.getPendingFee(marketId, taker2), -198.58205868107035e18);
        assertEq(vault.getPendingMargin(marketId, taker2), 198.58205868107035e18);

        // total paid funding fee >= total received funding fee
        assertGe(
            fundingFee.getPendingFee(marketId, address(taker1)) + fundingFee.getPendingFee(marketId, address(maker2)),
            -(fundingFee.getPendingFee(marketId, address(maker)) + fundingFee.getPendingFee(marketId, address(taker2)))
        );
    }

    function test_NoPositionInBasePool() public {
        // taker1 short 10 eth on maker2
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(100);

        assertEq(fundingFee.getCurrentFundingRate(marketId), 0);

        assertEq(fundingFee.getPendingFee(marketId, address(maker)), 0);
        assertEq(vault.getPendingMargin(marketId, address(maker)), 0);

        assertEq(fundingFee.getPendingFee(marketId, address(maker2)), 0);
        assertEq(vault.getPendingMargin(marketId, address(maker2)), 0);

        assertEq(fundingFee.getPendingFee(marketId, taker1), 0);
        assertEq(vault.getPendingMargin(marketId, taker1), 0);
    }
}
