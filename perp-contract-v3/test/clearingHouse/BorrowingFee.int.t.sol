// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ClearingHouseIntSetup.sol";

contract BorrowingFeeInt is ClearingHouseIntSetup {
    TestMaker public maker;
    TestMaker public maker2;
    address public taker1 = makeAddr("taker1");
    address public taker2 = makeAddr("taker2");

    function setUp() public override {
        super.setUp();

        // prepare 1 maker
        maker = _newMarketWithTestMaker(marketId);
        maker2 = _newMarketWithTestMaker(marketId);
        // set target borrowing fee rate rate = 0.00000001 per second
        config.setMaxBorrowingFeeRate(marketId, 10000000000, 10000000000);

        _deposit(marketId, taker1, 1000e6);
        _deposit(marketId, taker2, 1000e6);
        _deposit(marketId, address(maker), 10000e6);
        _deposit(marketId, address(maker2), 10000e6);

        // set price = 100
        maker.setBaseToQuotePrice(100e18);
        maker2.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);
    }

    //
    // PRIVATE
    //
    function _assertTakerGrowthIndexAreSynced(address taker) private {
        (uint256 globalLong, uint256 globalShort) = borrowingFee.getPayerFeeGrowthGlobal(marketId);
        (uint256 long, uint256 short) = borrowingFee.getPayerFeeGrowth(marketId, taker);
        assertEq(long, globalLong);
        assertEq(short, globalShort);
    }

    //
    // PUBLIC
    //

    function test_TakerMakerIsTheSame() public {
        // taker long 1 ether at $100 against himself
        bytes memory makerData = abi.encode(IClearingHouse.MakerOrder({ amount: 100 ether }));

        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(taker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp,
                makerData: makerData
            })
        );

        assertEq(vault.getPositionSize(marketId, address(taker1)), 0);
        assertEq(vault.getOpenNotional(marketId, address(taker1)), 0);

        (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(longGlobal.totalOpenNotional, 0 ether);
        assertEq(shortGlobal.totalOpenNotional, 0 ether);
    }

    function test_diffTakerOpenAndShortInSameMaker() public {
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

        (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(longGlobal.totalOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalOpenNotional, 0 ether);

        // taker2 short 9 eth on maker1
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 9 ether,
                oppositeAmountBound: 900 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // receive reduce short position in trader2, total receiver open notional should decrease
        (longGlobal, shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 100 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(longGlobal.totalOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalOpenNotional, 900 ether);

        skip(1 days);

        // only taker holding long has to pay borrowing fee
        assertLt(vault.getPendingMargin(marketId, address(taker1)), 0);
        assertEq(vault.getPendingMargin(marketId, address(taker2)), 0);
    }

    function test_oneTakerCloseShortAndOneTakerShortInSameMaker() public {
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
        // taker1 = -10, maker1 = 10, maker2 = 0
        (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(longGlobal.totalOpenNotional, 0 ether);
        assertEq(shortGlobal.totalOpenNotional, 1000 ether);

        // taker 1 close position on maker2 (long on maker2)
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker2),
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // taker1 = 0, maker1 = 10, maker2 = -10
        (longGlobal, shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(longGlobal.totalOpenNotional, 0 ether);
        assertEq(shortGlobal.totalOpenNotional, 0 ether);

        // taker2 short position on maker2
        vm.prank(taker2);
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
        // taker1 = 0, taker1 = -10, maker1 = 10, maker2 = 0
        (longGlobal, shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(longGlobal.totalOpenNotional, 0 ether);
        assertEq(shortGlobal.totalOpenNotional, 1000 ether);
    }

    function test_oneTakerCloseLongAndOneTakerLongInSameMaker() public {
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
        // taker1 = 10, maker1 = -10, maker2 = 0
        (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(longGlobal.totalOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalOpenNotional, 0 ether);

        // taker 1 close position on maker2 (short on maker2)
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker2),
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // taker1 = 0, maker1 = -10, maker2 = 10
        (longGlobal, shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(longGlobal.totalOpenNotional, 0 ether);
        assertEq(shortGlobal.totalOpenNotional, 0 ether);

        // taker 2 long position on maker2
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // taker1 = 0, taker2 = 10, maker1 = -10, maker2 = 0
        (longGlobal, shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(longGlobal.totalReceiverOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalReceiverOpenNotional, 0 ether);
        assertEq(longGlobal.totalOpenNotional, 1000 ether);
        assertEq(shortGlobal.totalOpenNotional, 0 ether);
    }

    function test_LastTakerFeeGrowthIndexShouldSyncWithGlobal() public {
        // give taker1 long 1 eth
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // when 1 day later, taker2 take another 1 eth long
        skip(1 days);
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // then global taker fee growth index should be 1d for long
        (uint256 globalLong, uint256 globalShort) = borrowingFee.getPayerFeeGrowthGlobal(marketId);
        assertEq(globalLong, 864e10 ether);
        assertEq(globalShort, 0);

        // then local taker fee growth index should be synced with the global states of the same side
        (uint256 taker2Day1SnapshotLong, ) = borrowingFee.getPayerFeeGrowth(marketId, taker2);
        assertEq(taker2Day1SnapshotLong, 864e10 ether);
    }

    function test_GetPendingTakerFeeIncreaseLongOnlyAfterAnotherShort() public {
        //    +------+----------------+-----------------+----------------+
        //    | Time |     Action     |     Global      |     Taker1     |
        //    +------+----------------+-----------------+----------------+
        //    | t0   | taker1 long 1  | long:0 short:0  | long:0 short:0 |
        //    | t0   | taker2 short 1 | long:0 short:0  | long:0 short:0 |
        //    | t1   | 1 day later    | long:1 short:1* | long:0 short:0 |
        //    +------+----------------+-----------------+----------------+

        // taker1 long 1 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 short 1 eth on maker2
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: true, // short
                isExactInput: true, // exact input (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        // then taker1 has some pending borrowing fee
        int256 pendingFee = vault.getPendingMargin(marketId, taker1);
        assertEq(pendingFee, -864000000000000);
    }

    function test_GetPendingTakerFeeIsBothZeroWhenOpenNewPositionFromOldAccount() public {
        //    +------+----------------+-----------------+-----------------+
        //    | Time |     Action     |     Global      |     Taker1      |
        //    +------+----------------+-----------------+-----------------+
        //    | t0   | taker1 long 1  | long:0 short:0  | long:0 short:0  |
        //    | t0   | taker2 short 1 | long:0 short:0  | long:0 short:0  |
        //    | t1   | 1 day later    | long:1 short:1  | long:0 short:0  |
        //    | t1   | taker1 short 1 | long:1 short:1  | long:1 short:1  |
        //    | t2   | 1 day later    | long:1 short: 2 | long:1 short:1  |
        //    | t2   | taker1 short 1 | long:1 short: 2 | long:1 short: 2 |
        //    +------+----------------+-----------------+-----------------+

        // taker1 long 1 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 short 1 eth on maker2
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: true, // short
                isExactInput: true, // exact input (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        // taker1 close long position
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // given taker long / short growth index are not initial state (0)
        // when a day later, taker2 keeps accumulating short borrowing fee, now taker1 short 1 eth on maker1
        skip(1 days);
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true, // short
                isExactInput: true, // exact input (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // then taker1's current pending taker fee is 0 at the moment right after she open
        int256 pendingFee = vault.getPendingMargin(marketId, taker1);
        assertEq(pendingFee, 0);

        // then taker1's fee growth index should sync with global long & short fee growth index
        _assertTakerGrowthIndexAreSynced(taker1);
    }

    function test_TakerFeeGrowthIndexUpdateAfterReversingPosition() public {
        // taker1 long 1 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 short 1 eth on maker2
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: true, // short
                isExactInput: true, // exact input (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        // taker1 reverse position, 2 short in eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true, // short
                isExactInput: true, // exact input (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // then taker1's fee growth index should sync with global long & short fee growth index
        _assertTakerGrowthIndexAreSynced(taker1);
    }

    function test_MakerHasUnsettledBorrowingFee() public {
        // taker1 long 1 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 long 1 eth on maker1
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        int256 pendingFee = vault.getPendingMargin(marketId, address(taker1));

        // taker1 close position and trigger borrowing fee settlement
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker receive borrowing fee: 0.1458
        // maker's margin: 10000 + 0.1458 (taker1, in unsettledPnl) + 0.1458 (taker2, in pending) = 10000.2916
        _assertEq(
            _getPosition(marketId, address(maker)),
            PositionProfile({
                margin: 10000e18 + (-pendingFee - pendingFee),
                positionSize: -1 ether,
                openNotional: 100 ether,
                unsettledPnl: -pendingFee // borrowing fee cannot be settled into margin, so it's in the pnl pool
            })
        );

        _assertEq(
            _getPosition(marketId, address(taker1)),
            PositionProfile({ margin: 1000e18 - (-pendingFee), positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }

    function test_MakerSettleAllPnlIntoMargin() public {
        // taker1 long 1 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false, // quote to base (long)
                isExactInput: false, // exact output (base)
                amount: 1 ether, // ask for 1 base
                oppositeAmountBound: 100 ether, // cost no more than 100 USDC
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(1 days);

        int256 pendingFee = vault.getPendingMargin(marketId, address(taker1));

        // taker1 close position and trigger borrowing fee settlement
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker receive borrowing fee: 0.1458
        // maker's margin: 10010 + 0.1458 = 10010.1458
        _assertEq(
            _getPosition(marketId, address(maker)),
            PositionProfile({ margin: 10000e18 + (-pendingFee), positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );

        _assertEq(
            _getPosition(marketId, address(taker1)),
            PositionProfile({ margin: 1000e18 - (-pendingFee), positionSize: 0, openNotional: 0, unsettledPnl: 0 })
        );
    }
}
