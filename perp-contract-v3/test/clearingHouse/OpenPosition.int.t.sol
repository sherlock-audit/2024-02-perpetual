// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ClearingHouseIntSetup.sol";
import "../../src/borrowingFee/IBorrowingFeeEvent.sol";

contract OpenPositionInt is ClearingHouseIntSetup, IBorrowingFeeEvent {
    using SafeCast for *;
    TestMaker public maker;
    address public taker = makeAddr("taker");
    address public taker2 = makeAddr("taker2");

    function setUp() public override {
        super.setUp();

        maker = _newMarketWithTestMaker(marketId);
        maker.setBaseToQuotePrice(150e18);
        _mockPythPrice(150, 0);

        // 0.00000001 per second
        config.setMaxBorrowingFeeRate(marketId, 10000000000, 10000000000);

        _deposit(marketId, address(maker), 10000e6);
        _deposit(marketId, taker, 1000e6);
        _deposit(marketId, taker2, 1000e6);
    }

    function test_SettleZeroBorrowingFee() public {
        assertEq(vault.getPendingMargin(marketId, address(taker)), 0);

        // taker long 10 ether

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(maker),
            address(maker),
            -10 ether, // positionSizeDelta
            1500 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(maker),
            10 ether, // positionSizeDelta
            -1500 ether, // openNotionalDelta
            0 ether, // realizedPnl
            PositionChangedReason.Trade // reason
        );

        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // the borrowingFee will be deducted from margin directly,
        // so we expect margin won't change after openPosition
        // since the taker has no position before
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({ margin: 1000 ether, positionSize: 10 ether, openNotional: -1500 ether, unsettledPnl: 0 })
        );
    }

    function test_SettleBorrowingFeeForTakerWithLongPosition() public {
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1500 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        // taker increase 10 ether,
        // and openPosition() will settle the borrowingFee for the previous position
        // utilRatio = 1500 / 10000 ~= 0.15 (with be a bit less by receiving borrowing fee)
        // borrowingFee = 0.15 * 0.00000001 * 1500 * 86400 (1 days) = 0.1944
        int256 pendingBorrowingFee = vault.getPendingMargin(marketId, address(taker));
        assertEq(pendingBorrowingFee, -194400000000000000);

        // margin = 1000 - 0.1944 = 999.8056
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({
                margin: 999805600000000000000,
                positionSize: 10 ether,
                openNotional: -1500 ether,
                unsettledPnl: 0
            })
        );

        // taker long 10 ether
        vm.expectEmit(true, true, true, true, address(borrowingFee));
        emit BorrowingFeeSettled(marketId, address(taker), 194400000000000000);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1500 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // util ratio double (15% to 30%) but slightly decreased by receiving borrowing fee
        (uint256 longUtilRatio, uint256 shortUtilRatio) = borrowingFee.getUtilRatio(marketId);
        assertEq(longUtilRatio, 299994168113371876);
        assertEq(shortUtilRatio, 0);
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({
                margin: 999805600000000000000,
                positionSize: 20 ether,
                openNotional: -3000 ether,
                unsettledPnl: 0
            })
        );
    }

    function test_SettleBorrowingFeeForTakerWithReversedPosition() public {
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        // taker open 20 ether short (reversed), result in 10 short
        // and openPosition() will settle the borrowingFee for the previous position
        // utilRatio = 1500 / 10000 = 0.15
        // borrowingFee = 0.15 * 0.00000001 * 1500 * 86400 (1 days) = 0.1944
        int256 pendingBorrowingFee = vault.getPendingMargin(marketId, address(taker));
        assertEq(pendingBorrowingFee, -194400000000000000);
        // margin = 1000 - 0.1944 = 999.8056
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({
                margin: 999805600000000000000,
                positionSize: 10 ether,
                openNotional: -1500 ether,
                unsettledPnl: 0
            })
        );

        // settlement is in separated process:
        // 1. close long (long util ratio -> 0)
        // 1-2. then settled borrowing fee (ordering doesn't matter)
        // 2. increase short (short util ratio -> 15%)
        // 3. after pending fee is being settled by vault, slightly reduce short util ratio
        vm.expectEmit(true, true, true, true, address(borrowingFee));
        emit BorrowingFeeSettled(marketId, address(taker), 194400000000000000);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 20 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        {
            // ( new util ratio = 1500 / 10000.1944 ~= 0.1499970841 )
            (uint256 longUtilRatio, uint256 shortUtilRatio) = borrowingFee.getUtilRatio(marketId);
            assertEq(longUtilRatio, 0);
            assertEq(shortUtilRatio, 149997084056685938);
        }
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({
                margin: 999805600000000000000,
                positionSize: -10 ether,
                openNotional: 1500 ether,
                unsettledPnl: 0
            })
        );

        skip(1 days);

        // taker open 20 ether long (reversed), result in 10 long
        // and openPosition() will settle the borrowingFee for the previous position
        // borrowingFee = 0.1499970841 * 0.00000001 * 1500 * 86400 (1 days) ~= 0.194396221
        pendingBorrowingFee = vault.getPendingMargin(marketId, address(taker));
        assertEq(pendingBorrowingFee, -194396220937464975);
        // margin = 1000 - 0.1944 - 0.194396221 ~= 999.611203779
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({
                margin: 999611203779062535025,
                positionSize: -10 ether,
                openNotional: 1500 ether,
                unsettledPnl: 0
            })
        );

        // settlement is in separated process:
        // 1. close short (short util ratio -> 0)
        // 1-2. then settled borrowing fee (ordering doesn't matter)
        // 2. increase long (short util ratio -> 15%)
        // 3. after pending fee is being settled by vault, slightly reduce long util ratio
        // new util ratio = 1500 / (10000 + 0.1944 + 0.194396221) ~= 0.1499941682834
        vm.expectEmit(true, true, true, true, address(borrowingFee));
        emit BorrowingFeeSettled(marketId, address(taker), 194396220937464975);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 20 ether,
                oppositeAmountBound: 4000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        {
            // ( new util ratio = 1500 / 10000.1944 ~= 0.1499970841 )
            (uint256 longUtilRatio, uint256 shortUtilRatio) = borrowingFee.getUtilRatio(marketId);
            assertEq(longUtilRatio, 149994168283420874);
            assertEq(shortUtilRatio, 0);
        }
        _assertEq(
            _getPosition(marketId, address(taker)),
            PositionProfile({
                margin: 999611203779062535025,
                positionSize: 10 ether,
                openNotional: -1500 ether,
                unsettledPnl: 0
            })
        );
    }

    function test_SettleBorrowingFeeForMaker() public {
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1500 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 short 5 ether
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 5 ether,
                oppositeAmountBound: 750 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        // takers haven't settled their borrowingFee yet
        int256 takerPendingBorrowingFee = vault.getPendingMargin(marketId, address(taker));
        int256 taker2PendingBorrowingFee = vault.getPendingMargin(marketId, address(taker2));

        // maker deposit 10 ether
        // and deposit() will settle the borrowingFee for the previous position
        // utilRatio = 750 / 10000 = 0.075
        // long borrowingFee = 0.075 * 0.00000001 * 1500 * 86400 (1 days) = 0.0972
        // short borrowingFee = 0
        // new util ratio is getting slightly lower because margin increased by borrowing fee
        // new util ratio = 750 / (10000 + 10 + 0.0972) = 0.074924
        vm.expectEmit(true, true, true, true, address(borrowingFee));
        emit BorrowingFeeSettled(marketId, address(maker), -0.0972 ether);
        vm.expectEmit(true, true, true, true, address(borrowingFee));
        emit UtilRatioChanged(marketId, 74924347387955433, 0, 0.075 ether, 0);

        int256 pendingBorrowingFee = vault.getPendingMargin(marketId, address(maker));
        assertEq(pendingBorrowingFee, 0.0972 ether);
        _assertEq(
            _getPosition(marketId, address(maker)),
            PositionProfile({
                margin: 10000.0972 ether,
                positionSize: -5 ether,
                openNotional: 750 ether,
                unsettledPnl: 0
            })
        );

        // maker receives = taker pays
        assertEq(pendingBorrowingFee, -(takerPendingBorrowingFee + taker2PendingBorrowingFee));

        // maker deposit to trigger borrowing fee settlement
        _deposit(marketId, address(maker), 10e6);

        // maker receive borrowing fee: 0.1458
        // maker's margin: 10010 + 0.1458 = 10010.1458
        _assertEq(
            _getPosition(marketId, address(maker)),
            PositionProfile({
                margin: 10010.0972 ether,
                positionSize: -5 ether,
                openNotional: 750 ether,
                unsettledPnl: 0.0972 ether // borrowing fee cannot be settled into margin, so it's in the pnl pool
            })
        );
    }

    function test_GetAccountValue() public {
        // we don't deposit margin in this test, margin = 0
        // account value = margin (include realized pnl and borrowing fee) + unrealized pnl

        // before open position
        _assertEq(
            _getMarginProfile(marketId, taker, 150 ether),
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 1000 ether,
                unrealizedPnl: 0,
                freeCollateral: 1000 ether,
                freeCollateralForOpen: 1000 ether, // min(1000, 1000) - 0 = 1000
                freeCollateralForReduce: 1000 ether, // min(1000, 1000) - 0 = 1000
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );

        // taker long 10 ether with avg price 150
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // after increase position
        // current price = 200
        // unrealized pnl = 10 * (200 - 150) = 500
        _assertEq(
            _getMarginProfile(marketId, taker, 200 ether),
            LegacyMarginProfile({
                positionSize: 10 ether,
                openNotional: -1500 ether,
                accountValue: 1500 ether,
                unrealizedPnl: 500 ether,
                freeCollateral: 850 ether,
                freeCollateralForOpen: 850 ether, // min(1000, 1500) - 1500 * 0.1 = 850
                freeCollateralForReduce: 906.25 ether, // min(1000, 1500) - 1500 * 0.0625 = 906.25
                marginRatio: 1 ether
            })
        );

        skip(1 days);

        // after 1 day, taker has some pending borrowing fee
        // utilRatio = 1500 / 10000 = 0.15
        // borrowingFee = 0.15 * 0.00000001 * 1500 * 86400 (1 days) = 0.1944
        int256 borrowingFeeAmount = 194400000000000000;
        _assertEq(
            _getMarginProfile(marketId, taker, 200 ether),
            LegacyMarginProfile({
                positionSize: 10 ether,
                openNotional: -1500 ether,
                accountValue: 1500 ether - borrowingFeeAmount,
                unrealizedPnl: 500 ether,
                freeCollateral: (850 ether - borrowingFeeAmount).toUint256(),
                freeCollateralForOpen: 850 ether - borrowingFeeAmount, // min(1000 - borrowingFeeAmount, 1500 - borrowingFeeAmount) - 1500 * 0.1 = 850 - borrowingFeeAmount
                freeCollateralForReduce: 906.25 ether - borrowingFeeAmount, // min(1000 - borrowingFeeAmount, 1500 - borrowingFeeAmount) - 1500 * 0.0625 = 906.25 - borrowingFeeAmount
                marginRatio: 0.9998704 ether // 1,499.8056/1500=0.99987
            })
        );

        // taker close 10 ether long with avg price 200
        maker.setBaseToQuotePrice(200e18);
        vm.prank(taker);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(maker),
            -500 ether, // realizedPnl
            -500 ether, // settledPnl
            10000 ether + uint256(borrowingFeeAmount) - 500 ether, // marign
            0, // unsettledPnl
            500 ether // pnlPoolBalance
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            500 ether, // realizedPnl
            500 ether, // settledPnl
            1000 ether - uint256(borrowingFeeAmount) + 500 ether, // margin
            0, // unsettledPnl
            0 ether // pnlPoolBalance
        );

        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // after decrease position
        _assertEq(
            _getMarginProfile(marketId, taker, 200 ether),
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 1500 ether - borrowingFeeAmount,
                unrealizedPnl: 0, // it's realized
                freeCollateral: (1500 ether - borrowingFeeAmount).toUint256(),
                freeCollateralForOpen: 1500 ether - borrowingFeeAmount, // min(1500 - borrowingFeeAmount, 1500 - borrowingFeeAmount) - 0 = 1500 - borrowingFeeAmount
                freeCollateralForReduce: 1500 ether - borrowingFeeAmount, // min(1500 - borrowingFeeAmount, 1500 - borrowingFeeAmount) - 0 = 1500 - borrowingFeeAmount
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );
    }

    function test_QuoteOpenPosition() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.QuoteResult.selector, -10 ether, 1500 ether));
        vm.prank(taker);
        clearingHouse.quoteOpenPosition(
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
    }

    function test_RevertIf_OracleDataRequired() public {
        vm.clearMockedCalls();
        vm.mockCallRevert(
            address(pyth),
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId),
            abi.encode("test")
        );

        vm.expectRevert(abi.encodeWithSelector(LibError.OracleDataRequired.selector, priceFeedId, abi.encode("test")));
        // taker long 10 ether
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_B2QWithInsufficientQuote() public {
        // taker short 10 ether, expecting at least 2000 usd
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(LibError.InsufficientOutputAmount.selector, 1500 ether, 2000 ether));
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_B2QWithExcessiveBase() public {
        // taker short ether with 1500 usd, expecting at most 5 ether
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(LibError.ExcessiveInputAmount.selector, 10 ether, 5 ether));
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: false,
                amount: 1500 ether,
                oppositeAmountBound: 5 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_Q2BWithInsufficientBase() public {
        // taker long with 1500 usd, expecting at least 20 ether
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(LibError.InsufficientOutputAmount.selector, 10 ether, 20 ether));
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: true,
                amount: 1500 ether,
                oppositeAmountBound: 20 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_Q2BWithExcessiveQuote() public {
        // taker long 10 ether, expecting at most 1000 ether
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(LibError.ExcessiveInputAmount.selector, 1500 ether, 1000 ether));
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
    }

    function test_RevertIf_TakerMarginNotEnough() public {
        // taker long 100 ether
        vm.prank(taker);
        // free collateral after open position: 1000 - 15000 * 10% = -500 (reverted)
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: 15000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_MakerMarginNotEnough() public {
        // taker long 1000 ether
        _deposit(marketId, taker, 100000e6);
        vm.prank(taker);
        // maker's free collateral after open position: 10000 - 150 * 1000 * 10% = -5000 (reverted)
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, maker));
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1000 ether,
                oppositeAmountBound: 150000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_ZeroAmount() public {
        vm.expectRevert(LibError.ZeroAmount.selector);
        // open position with 0 amount
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: false,
                amount: 0,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_DeadlineExceeded() public {
        vm.expectRevert(LibError.DeadlineExceeded.selector);
        // open position with 0 as deadline
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: 0,
                makerData: ""
            })
        );
    }

    function test_OpenPositionFor_RevertIf_AuthorizerNotAllow() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.AuthorizerNotAllow.selector, taker2, taker));
        vm.prank(taker);
        clearingHouse.openPositionFor(
            IClearingHouse.OpenPositionForParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: "",
                taker: address(taker2),
                takerRelayFee: 0,
                makerRelayFee: 0
            })
        );
    }

    function test_ClosePositionFor_RevertIf_AuthorizerNotAllow() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.AuthorizerNotAllow.selector, taker2, taker));
        vm.prank(taker);
        clearingHouse.closePositionFor(
            IClearingHouse.ClosePositionForParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: "",
                taker: address(taker2),
                takerRelayFee: 0,
                makerRelayFee: 0
            })
        );
    }

    function test_RevertIf_OverPriceBand() public {
        // given oracle price = 150 and price band ratio = 10%, means trade will fail if price is out of 135 ~ 165
        config.setPriceBandRatio(marketId, 0.1 ether);

        maker.setBaseToQuotePrice(165 ether + 1);
        vm.expectRevert(abi.encodeWithSelector(LibError.PriceOutOfBound.selector, 165 ether + 1, 135 ether, 165 ether));
        _longExactOutput();

        maker.setBaseToQuotePrice(135 ether - 1);
        vm.expectRevert(abi.encodeWithSelector(LibError.PriceOutOfBound.selector, 135 ether - 1, 135 ether, 165 ether));
        _shortExactInput();
    }

    function _longExactOutput() internal {
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function _shortExactInput() internal {
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }
}
