// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../clearingHouse/ClearingHouseIntSetup.sol";

contract MakerIsPayerInt is ClearingHouseIntSetup {
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    TestMaker public receiver;
    uint64 public price;

    function setUp() public override {
        super.setUp();

        receiver = _newMarketWithTestMaker(marketId);
        _deposit(marketId, address(receiver), 100000e6);
        _deposit(marketId, alice, 100000e6);
        _deposit(marketId, bob, 100000e6);
        _setPrice(100);
    }

    function _setPrice(uint64 priceArg) internal {
        price = priceArg;
        receiver.setBaseToQuotePrice(uint256(priceArg) * 1 ether);
        _mockPythPrice(int64(priceArg), 0);
    }

    function _trade(address trader_, address maker_, int256 size_) internal {
        super._trade(trader_, maker_, size_, price);
    }

    function test_PayerReduceByAnotherPayer() public {
        // given alice long 10 eth@$100, totalOpenNotionalLong = 1,000
        _trade(alice, address(receiver), 10 ether);
        // when bob long 5 eth$50 on alice
        _setPrice(50);
        _trade(bob, alice, 5 ether);
        // then totalOpenNotionalLong = 1,000 - 500 (alice) + 250 (bob) = 750
        (LibUtilizationGlobal.Info memory long, ) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(long.totalOpenNotional, 750 ether);
    }

    function test_TwoPayers_BothIncreasePosition() public {
        // when bob long 5 eth$50 on alice
        _setPrice(50);
        _trade(bob, alice, 5 ether);

        // then totalOpenNotionalLong = +250 (bob)
        (LibUtilizationGlobal.Info memory long, ) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(long.totalOpenNotional, 250 ether);

        // then totalOpenNotionalShort = +250 (alice)
        (, LibUtilizationGlobal.Info memory short) = borrowingFee.getUtilizationGlobal(marketId);
        assertEq(short.totalOpenNotional, 250 ether);
    }

    function test_TwoPayers_BothReducePosition() public {}

    function test_TwoPayers_OneIncreaseAnotherReverse() public {
        // trade1
        // given alice long 10 eth@$100, long.totalOpenNotional = 1000
        _trade(alice, address(receiver), 10 ether);

        // trade2
        // when bob long 30 eth$200 on alice
        // bob 0 + 30 = 30 ETH
        // alice 10 - 30 = -20 ETH (reverse position)
        _setPrice(200);
        _trade(bob, alice, 30 ether);

        assertEq(vault.getPositionSize(marketId, bob), 30 ether);
        assertEq(vault.getOpenNotional(marketId, bob), -6000 ether);
        assertEq(vault.getPositionSize(marketId, alice), -20 ether);
        assertEq(vault.getOpenNotional(marketId, alice), 4000 ether);

        (LibUtilizationGlobal.Info memory long, LibUtilizationGlobal.Info memory short) = borrowingFee
            .getUtilizationGlobal(marketId);

        // in trade2, it's a p2p trade. totalReceiverOpenNotional won't change
        assertEq(long.totalReceiverOpenNotional, 1000 ether);
        assertEq(short.totalReceiverOpenNotional, 0 ether);

        // long.totalOpenNotional = +1000 (alice trade1) -1000 (alice trade2) +6000 (bob trade2) = 6000
        assertEq(long.totalOpenNotional, 6000 ether);

        // short.totalOpenNotional = +4000 (alice trade2) = 4000
        assertEq(short.totalOpenNotional, 4000 ether);
    }
}
