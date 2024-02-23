// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;
import "./BorrowingFeeSpecSetup.sol";

// beforeSettle:
// (if payer) did settle global payer fee, local payer fee, global payer pos
// (if receiver) did settle global receiver fee, local receiver fee, local receiver pos
// return settledFee
//
// afterSettle:
// (if any receiver) did update global receiver util ratio
contract SettleSpec is BorrowingFeeSpecSetup {
    //
    // Input Check
    //

    function test_BeforeSettle_RevertIf_InvalidPosition() public {
        vm.expectRevert(LibError.InvalidPosition.selector);
        _beforeSettle(payer1, receiver1, -1, -1);
        vm.expectRevert(LibError.InvalidPosition.selector);
        _beforeSettle(payer1, receiver1, 1, 1);
    }

    //
    // Trader Check
    //
    function test_BeforeSettle_RevertIf_ReceiverToReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidTaker.selector, receiver1));
        _beforeSettle(receiver1, receiver1, 1, -1);
    }

    function test_BeforeSettle_RevertIf_ReceiverToPayer() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidTaker.selector, receiver1));
        _beforeSettle(receiver1, payer1, 1, -1);
    }

    //
    // BeforeSettle  - no fee in the beginning
    //
    function test_BeforeSettle_PayerToPayer_NoFeeInTheBeginning() public {
        (int256 takerBrFee, int256 makerBrFee) = _beforeSettle(payer1, payer2, 1, -1);
        assertEq(takerBrFee, 0);
        assertEq(makerBrFee, 0);
    }

    function test_BeforeSettle_PayerToReceiver_NoFeeInTheBeginning() public {
        (int256 takerBrFee, int256 makerBrFee) = _beforeSettle(payer1, receiver1, 1, -1);
        assertEq(takerBrFee, 0);
        assertEq(makerBrFee, 0);
    }

    //
    // Before & AfterSettle  - update global maker util ratio stats if there's any maker participated in
    //
    function test_AfterSettle_PayerToPayer_UpdateGlobalUtilRatio() public {
        (uint256 oldLongUtilRatio, uint256 oldShortUtilRatio) = _getUtilRatio(marketId);
        _beforeSettle(payer1, payer2, 1, -1);
        _afterSettle(payer2);
        (uint256 newLongUtilRatio, uint256 newShortUtilRatio) = _getUtilRatio(marketId);
        assertEq(oldLongUtilRatio, newLongUtilRatio);
        assertEq(oldShortUtilRatio, newShortUtilRatio);
    }

    function test_AfterSettle_PayerToReceiver_UpdateGlobalLongUtilRatio() public {
        // given payer long, receiver short
        _beforeSettle(payer1, receiver1, 1, -1);

        // when receiver's util ratio = 100% and it's the only receiver
        _mockLocalUtilRatioFactor(receiver1, 1 ether, 0);

        // then total long util ratio is updated (100%)
        _afterSettle(receiver1);
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 1 ether);
        assertEq(shortUtilRatio, 0);
    }

    function test_AfterSettle_PayerToReceiver_UpdateGlobalShortUtilRatio() public {
        // given payer short, receiver long
        _beforeSettle(payer1, receiver1, -1, 1);

        // when receiver's util ratio = 100% and it's the only receiver
        _mockLocalUtilRatioFactor(receiver1, 0, 1 ether);

        // then total short util ratio is updated (100%)
        _afterSettle(receiver1);
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        assertEq(longUtilRatio, 0);
        assertEq(shortUtilRatio, 1 ether);
    }

    //
    // BeforeSettle return
    //
    function test_Settle_PayerToReceiver_SettlePendingFee() public {
        // given payer long, receiver short, the only receiver util ratio goes to 100%
        _settleWithReceiver(marketId, payer1, receiver1, 1, -1, receiver1, 1 ether);

        // when 1 seconds later (100% rate), the same payer close position
        skip(1 seconds);
        (int256 takerFee, int256 makerFee) = _beforeSettle(payer1, receiver1, -1, 1);

        // then taker pay 1, maker receive 1
        assertEq(takerFee, 1);
        assertEq(makerFee, -1);
    }

    //
    // BeforeSettle mutated states
    //
    function test_BeforeSettle_PayerIncreaseToReceiver() public {
        (LibUtilizationGlobal.Info memory oldLong, ) = borrowingFee.getUtilizationGlobal(marketId);

        // payer increase to receiver, global stats increased. did not affect short side
        _settleWithReceiver(marketId, payer1, receiver1, 1, -1, receiver1, 1 ether);
        (LibUtilizationGlobal.Info memory newLong, LibUtilizationGlobal.Info memory newShort) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(oldLong.totalReceiverOpenNotional + 1, newLong.totalReceiverOpenNotional);
        assertEq(oldLong.totalOpenNotional + 1, newLong.totalOpenNotional);
        assertEq(newShort.totalReceiverOpenNotional, 0);
        assertEq(newShort.totalOpenNotional, 0);
    }

    function test_BeforeSettle_PayerReduceToReceiver() public {
        // given payer long, receiver short, the only receiver util ratio goes to 100%
        _settleWithReceiver(marketId, payer1, receiver1, 1, -1, receiver1, 1 ether);

        // payer increase to receiver, global stats decreased. did not affect short side
        _beforeSettle(payer1, receiver1, -1, 1);
        (LibUtilizationGlobal.Info memory newLong, LibUtilizationGlobal.Info memory newShort) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(newLong.totalReceiverOpenNotional, 0);
        assertEq(newLong.totalOpenNotional, 0);
        assertEq(newShort.totalReceiverOpenNotional, 0);
        assertEq(newShort.totalOpenNotional, 0);
    }

    function test_BeforeSettle_PayerIncreaseToPayerIncrease() public {
        // given payer1 long (increased), payer2 short (increased)
        (LibUtilizationGlobal.Info memory oldLong, LibUtilizationGlobal.Info memory oldShort) = borrowingFee
            .getUtilizationGlobal(marketId);
        _settle(marketId, payer1, payer2, 1, -1);

        // then global openNotional should increase even no receiver is involved
        (LibUtilizationGlobal.Info memory newLong, LibUtilizationGlobal.Info memory newShort) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(oldLong.totalOpenNotional + 1, newLong.totalOpenNotional);

        // since payer2 also increased, will also update short global stats
        assertEq(oldShort.totalOpenNotional + 1, newShort.totalOpenNotional);
    }

    function test_BeforeSettle_PayerIncreaseToPayerReduce() public {
        // given payer1 long (increase) to receiver1
        _settleWithReceiver(marketId, payer1, receiver1, 1, -1, receiver1, 1 ether);

        // when payer2 long (increased), payer1 short (reduced)
        // (this is similar to liquidation)
        (LibUtilizationGlobal.Info memory oldLong, LibUtilizationGlobal.Info memory oldShort) = borrowingFee
            .getUtilizationGlobal(marketId);
        assertEq(oldShort.totalReceiverOpenNotional, 0);
        assertEq(oldShort.totalOpenNotional, 0);
        _settle(marketId, payer2, payer1, 1, -1);

        // global long does not impacted since it's just transferring between payer1 to payer2
        (LibUtilizationGlobal.Info memory newLong, ) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(oldLong.totalReceiverOpenNotional, newLong.totalReceiverOpenNotional);
        assertEq(oldLong.totalOpenNotional, newLong.totalOpenNotional);

        // global short still remains the same
        assertEq(oldShort.totalReceiverOpenNotional, oldShort.totalReceiverOpenNotional);
        assertEq(oldShort.totalOpenNotional, oldShort.totalOpenNotional);
    }
}
