// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;
import "./BorrowingFeeSpecSetup.sol";

contract PayerPendingFeeSpec is BorrowingFeeSpecSetup {
    function test_PayerPendingFee_IncreaseLong() public {
        // given payer long, receiver short, the only receiver util ratio goes from 0 to 100%
        _beforeSettle(payer1, receiver1, 1, -1);
        _mockLocalUtilRatioFactor(receiver1, 1 ether, 0);
        _mockPosition(payer1, 1, -1);
        _mockPosition(receiver1, -1, 1);
        _afterSettle(receiver1);

        // borrowing fee rate is 100% per seconds
        skip(1 seconds);

        // then payer has 1 borrowing fee
        assertEq(borrowingFee.getPendingFee(marketId, payer1), 1);
    }

    function test_PayerPendingFee_IncreaseShort() public {}

    function test_PayerPendingFee_ReduceLong() public {}

    function test_PayerPendingFee_ReduceShort() public {}

    function test_PayerPendingFee_ReverseLong() public {}

    function test_PayerPendingFee_ReverseShort() public {}
}
