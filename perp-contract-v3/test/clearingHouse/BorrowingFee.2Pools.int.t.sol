// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { TestMaker } from "../helper/TestMaker.sol";
import "./ClearingHouseIntSetup.sol";
import "../../src/clearingHouse/IClearingHouse.sol";
import "../../src/vault/IMarginProfile.sol";

contract BorrowingFeeInt is ClearingHouseIntSetup {
    using FixedPointMathLib for int256;
    TestMaker public maker1;
    TestMaker public maker2;
    address public taker1 = makeAddr("taker1");
    address public taker2 = makeAddr("taker2");
    address public taker3 = makeAddr("taker3");

    function setUp() public override {
        super.setUp();

        maker1 = _newMarketWithTestMaker(marketId);
        maker2 = new TestMaker(vault);
        config.registerMaker(marketId, address(maker2));

        // maker deposits
        deal(address(collateralToken), address(maker1), 10000e6);
        deal(address(collateralToken), address(maker2), 10000e6);

        // maker1 deposit 10000
        vm.startPrank(address(maker1));
        collateralToken.approve(address(vault), 10000e6);
        vault.deposit(address(maker1), 10000e6);
        vault.transferFundToMargin(marketId, 10000e6);
        vm.stopPrank();

        // maker2 deposit 10000
        vm.startPrank(address(maker2));
        collateralToken.approve(address(vault), 10000e6);
        vault.deposit(address(maker2), 10000e6);
        vault.transferFundToMargin(marketId, 10000e6);
        vm.stopPrank();

        // 0.00000001 per second
        config.setMaxBorrowingFeeRate(marketId, 10000000000, 10000000000);

        maker1.setBaseToQuotePrice(100 ether);
        maker2.setBaseToQuotePrice(100 ether);
        _mockPythPrice(100, 0);

        _deposit(marketId, taker1, 10000e6);
        _deposit(marketId, taker2, 10000e6);
        _deposit(marketId, taker3, 10000e6);
    }

    function _getUtilRatio(uint256 marketId) private view returns (uint256, uint256) {
        (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        return (longGlobal.utilRatio, shortGlobal.utilRatio);
    }

    //
    // PUBLIC
    //

    function test_OpenIn2Pools() public {
        // taker1 long 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker1 util ratio = 1000/10000 = 0.1
        // maker2 util ratio = 0
        // long util ratio = 0.1
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 0.1 ether);
        assertEq(shortUtilRatio, 0);

        // taker1 long 20 eth on maker2
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 20 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker1 util ratio = 1000/10000 = 0.1
        // maker2 util ratio = 2000/10000 = 0.2
        // long util ratio = 0.1 * 10 + 0.2 * 20 / 30 = 0.166666666666666666
        (longUtilRatio, shortUtilRatio) = _getUtilRatio(marketId);
        assertApproxEqAbs(longUtilRatio, 166666666666666667, 10);
        assertEq(shortUtilRatio, 0);

        skip(1 days);

        // taker total open notional = 3000
        // total borrowing fee = 3000 * 0.166666666666666666 * 0.00000001 * 86400 = 0.432
        // maker1Fee = 0.432 * 10/30 = 0.144
        // maker2Fee = 0.432 * 20/30 = 0.288
        int256 pendingMakerFee1 = vault.getPendingMargin(marketId, address(maker1));
        int256 pendingMakerFee2 = vault.getPendingMargin(marketId, address(maker2));
        assertApproxEqAbs(pendingMakerFee1, 144000000000000000, 10);
        assertApproxEqAbs(pendingMakerFee2, 288000000000000000, 10);

        int256 pendingTakerFee = vault.getPendingMargin(marketId, address(taker1));
        assert(pendingTakerFee < 0);
        _assertApproxGteAbs(pendingTakerFee, 0.432 ether, 10);

        int256 totalPendingMakerFee = pendingMakerFee1 + pendingMakerFee2;
        _assertApproxGteAbs(pendingTakerFee, totalPendingMakerFee, 1, "total pending fee should be closed to 0");
    }

    function test_OpenAndCloseInDifferentPools() public {
        // taker1 long 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker1 util ratio = 1000/10000 = 0.1
        // maker2 util ratio = 0
        // long util ratio = 0.1
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 0.1 ether);
        assertEq(shortUtilRatio, 0, "shortUtilRatio should be 0");

        // taker1 close long on maker2
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

        // maker1 util ratio = 1000/10000 = 0.1
        // maker2 util ratio = 1000/10000 = 0.1
        // long util ratio = 0.1 * 10
        // short util ratio = 0.1 * 10
        (longUtilRatio, shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 0.1 ether);
        assertEq(shortUtilRatio, 0.1 ether);
    }

    function test_OpenWhenPoolsHaveOppositePosition() public {
        // taker1 long 10 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // taker1 close long on maker2
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
        // taker2 long 20 eth on maker1
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 20 ether,
                oppositeAmountBound: 2000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker1 util ratio = 3000/10000 = 0.3
        // maker2 util ratio = 1000/10000 = 0.1
        // long util ratio = 0.3
        // short util ratio = 0.1
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertApproxEqAbs(longUtilRatio, 0.3 ether, 1);
        assertEq(shortUtilRatio, 0.1 ether);

        skip(1 days);

        // taker total open notional long = 2000
        // total borrowing fee = 2000 * 0.3 * 0.00000001 * 86400 = 0.5184
        // maker1Fee = 0.5184
        // maker2Fee = 0
        int256 pendingMakerFee1 = vault.getPendingMargin(marketId, address(maker1));
        int256 pendingMakerFee2 = vault.getPendingMargin(marketId, address(maker2));
        assertApproxEqAbs(pendingMakerFee1, 0.5184 ether, 1);
        assertEq(pendingMakerFee2, 0);

        int256 pendingTakerFee1 = vault.getPendingMargin(marketId, address(taker1));
        assertEq(pendingTakerFee1, 0);
        int256 pendingTakerFee2 = vault.getPendingMargin(marketId, address(taker2));
        assertApproxEqAbs(pendingTakerFee2, -0.5184 ether, 2);
        _assertApproxGteAbs(
            pendingTakerFee1 + pendingTakerFee2,
            pendingMakerFee1 + pendingMakerFee2,
            1,
            "total pending fee should be closed to 0"
        );
    }

    function test_RoundUpUtilRatio() public {
        // taker1 long 50 eth on maker1
        vm.startPrank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 50 ether,
                oppositeAmountBound: 5000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker1 util ratio = 50%, weighted = 100%
        // maker2 util ratio = 0, weighted = 0%
        // long util ratio = 50%
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 5e17);
        assertEq(shortUtilRatio, 0);

        // taker1 long 10 eth on maker2
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

        // taker1 long 40 eth on maker2
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 40 ether,
                oppositeAmountBound: 4000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        vm.stopPrank();

        // maker1 util ratio = 50%, weighted = 50%
        // maker2 util ratio = 50%, weighted = 50%
        // long util ratio = 50%
        // it gets round up multiple times, but util ratio has this tiny error should be fine
        (longUtilRatio, shortUtilRatio) = _getUtilRatio(marketId);
        assertApproxEqAbs(longUtilRatio, 0.5 ether, 1);
        assertEq(shortUtilRatio, 0);
    }

    function test_RoundUpUtilRatio_OverHundredPercent() public {
        // taker1 long 100 eth on maker1
        vm.prank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: 10000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // maker1 util ratio = 100%, weighted = 100%
        // maker2 util ratio = 0, weighted = 0%
        // long util ratio = 100%
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 1e18);
        assertEq(shortUtilRatio, 0);

        // taker1 long 1 eth on maker2
        vm.startPrank(taker1);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker2),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 90 ether,
                oppositeAmountBound: 9000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
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
        vm.stopPrank();

        (longUtilRatio, shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 1 ether);
        assertEq(shortUtilRatio, 0);
    }

    function _transferAllFreeCollateralToFund(uint256 marketId_, address trader_, uint256 priceInWei) internal {
        uint256 freeCollateral = (vault.getFreeCollateral(marketId_, address(trader_), priceInWei) * 1e6) / 1e18;
        //        int256 freeCollateral = (vault.getFreeCollateralForTrade(
        //            marketId_,
        //            address(trader_),
        //            priceInWei,
        //            MarginRequirementType.INITIAL
        //        ) * 1e6) / 1e18;
        //        assert(freeCollateral >= 0);
        vm.prank(trader_);
        vault.transferMarginToFund(marketId_, freeCollateral);
    }

    function test_Reproduce_CI_Error_20240202_1() public {
        config.setMaxBorrowingFeeRate(marketId, 4224537037037037, 4224537037037037); // 1 ether / (86400 * 365)

        // taker long 1 eth on maker1
        _mockPythPrice(230594999999, -8); // 2305.94999999
        maker1.setBaseToQuotePrice(2305.94999999 ether);
        vm.prank(taker1);
        _openPosition(marketId, address(maker1), 1 ether);
        skip(1 seconds);
        _assertApproxGteAbs(
            vault.getPendingMargin(marketId, taker1),
            vault.getPendingMargin(marketId, address(maker1)),
            1,
            "after the first trade until settlement, taker's pending margin should be equals to maker1's pending margin"
        );

        // oracle maker deposit another 10k
        deal(address(collateralToken), address(maker1), 10000e6);
        vm.startPrank(address(maker1));
        collateralToken.approve(address(vault), 10000e6);
        vault.deposit(address(maker1), 10000e6);
        vault.transferFundToMargin(marketId, 10000e6);
        vm.stopPrank();

        assertEq(
            vault.getPendingMargin(marketId, address(maker1)),
            0,
            "makerPendingMargin is 0 after settled (deposit)"
        );
        _assertApproxGteAbs(
            vault.getPendingMargin(marketId, taker1),
            -vault.getUnsettledPnl(marketId, address(maker1)),
            1,
            "after maker settle (deposit), taker's pending margin should equals to maker's unsettledPnl"
        );
        skip(1 seconds);

        // taker2 short 1 eth on maker2
        _mockPythPrice(230833879992, -8); // 2308.33879992
        maker2.setBaseToQuotePrice(2308.33879992 ether);
        vm.prank(taker2);
        _openPosition(marketId, address(maker2), -1 ether);
        skip(1 seconds);

        // taker3 short 1 eth to maker2
        _mockPythPrice(230140479626, -8); // 2301.40479626
        maker2.setBaseToQuotePrice(2301.40479626 ether);
        vm.prank(taker3);
        _openPosition(marketId, address(maker2), -1 ether);
        skip(1 seconds);

        // taker1 close (short 1eth) on maker1
        _mockPythPrice(230368470677, -8); // 2303.68470677
        maker1.setBaseToQuotePrice(2303.68470677 ether);
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker1),
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        skip(1 seconds);

        // taker2 close(long 1eth) on maker2
        _mockPythPrice(230215302791, -8); // 2302.15302791
        maker2.setBaseToQuotePrice(2302.15302791 ether);
        vm.prank(taker2);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker2),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        skip(1 seconds);

        // taker3 close (long 1 eth) on maker2
        _mockPythPrice(230140479626, -8); // 2301.40479626
        maker2.setBaseToQuotePrice(2301.40479626 ether);
        vm.prank(taker3);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker2),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        skip(1 seconds);

        assertEq(vault.getPendingMargin(marketId, taker1), 0, "takerPendingMargin should be 0 after settled (close)");
        assertEq(vault.getUnsettledPnl(marketId, taker1), 0, "takerUnsettledPnl should be 0 after settled (close)");
        assertEq(
            vault.getPendingMargin(marketId, address(maker1)),
            0,
            "makerPendingMargin should be 0 after settled (close)"
        );

        uint256 finalPrice = 2308.33879992 ether;
        _transferAllFreeCollateralToFund(marketId, taker1, finalPrice);
        _transferAllFreeCollateralToFund(marketId, taker2, finalPrice);
        _transferAllFreeCollateralToFund(marketId, taker3, finalPrice);
        _transferAllFreeCollateralToFund(marketId, address(maker1), finalPrice);
        _transferAllFreeCollateralToFund(marketId, address(maker2), finalPrice);

        assertEq(vault.getUnsettledPnl(marketId, taker1), 0, "taker1 unsettled pnl != 0");
        assertEq(vault.getUnsettledPnl(marketId, taker2), 0, "taker2 unsettled pnl != 0");
        assertEq(vault.getUnsettledPnl(marketId, taker3), 0, "taker3 unsettled pnl != 0");
        assertEq(vault.getUnsettledPnl(marketId, address(maker1)), 0, "maker1 unsettled pnl != 0");
        assertEq(vault.getUnsettledPnl(marketId, address(maker2)), 0, "maker2 unsettled pnl != 0");
    }

    function test_Reproduce_CI_Error_20240202_2() public {
        config.setMaxBorrowingFeeRate(marketId, 4224537037037037, 4224537037037037); // 1 ether / (86400 * 365)

        // taker1 short 1 eth on maker1
        vm.prank(taker1);
        _openPosition(marketId, address(maker1), -1 ether);
        skip(1 seconds);

        // taker2 short 1 eth on maker1
        vm.prank(taker2);
        _openPosition(marketId, address(maker1), -1 ether);
        assertEq(
            -vault.getPendingMargin(marketId, taker1),
            vault.getUnsettledPnl(marketId, address(maker1)),
            "taker1 pending margin should = maker1's unsettled pnl after taker 2 trade"
        );
        skip(1 seconds);

        // taker1 close (long 1eth) on maker1
        vm.prank(taker1);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker1),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        skip(1 seconds);

        // taker2 close(long 1eth) on maker1
        vm.prank(taker2);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker1),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        skip(1 seconds);

        _transferAllFreeCollateralToFund(marketId, taker1, 100 ether);
        _transferAllFreeCollateralToFund(marketId, taker2, 100 ether);
        _transferAllFreeCollateralToFund(marketId, address(maker1), 100 ether);
        assertEq(vault.getUnsettledPnl(marketId, taker1), 0, "taker 1 UnsettledPnl should be 0 after settled (close)");
        assertEq(vault.getUnsettledPnl(marketId, taker2), 0, "taker 2 UnsettledPnl should be 0 after settled (close)");
        assertEq(
            vault.getUnsettledPnl(marketId, address(maker1)),
            0,
            "maker1 UnsettledPnl should be 0 after settled (close)"
        );
    }

    function test_ReceiverDepositWontImpactPayerFeeRightAway() public {
        config.setMaxBorrowingFeeRate(marketId, 4224537037037037, 4224537037037037); // 1 ether / (86400 * 365)

        // taker1 short 100 eth on maker1
        vm.prank(taker1);
        _openPosition(marketId, address(maker1), -100 ether);
        skip(1 seconds);

        // oracle maker deposit another 10k
        deal(address(collateralToken), address(maker1), 10000e6);
        vm.startPrank(address(maker1));
        collateralToken.approve(address(vault), 10000e6);
        vault.deposit(address(maker1), 10000e6);
        vault.transferFundToMargin(marketId, 10000e6);
        vm.stopPrank();

        assertEq(
            vault.getPendingMargin(marketId, taker1),
            -vault.getUnsettledPnl(marketId, address(maker1)),
            "after maker settle (deposit), taker's pending margin should equals to maker's unsettledPnl"
        );
    }

    function test_UtilRatioUpdated_AfterDeposit() public {
        config.setMaxBorrowingFeeRate(marketId, 0, 0);

        // given taker1 short 100 eth on maker1
        vm.prank(taker1);
        _openPosition(marketId, address(maker1), -100 ether);
        {
            (, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
            assertEq(shortGlobal.utilRatio, 1 ether);
        }

        // when oracle maker deposit another 10k
        deal(address(collateralToken), address(maker1), 10000e6);
        vm.startPrank(address(maker1));
        collateralToken.approve(address(vault), 10000e6);
        vault.deposit(address(maker1), 10000e6);
        vault.transferFundToMargin(marketId, 10000e6);
        vm.stopPrank();

        // then maker's util ratio downs to 50%
        {
            (, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee.getUtilizationGlobal(marketId);
            assertEq(shortGlobal.utilRatio, 0.5 ether);
        }
    }
}
