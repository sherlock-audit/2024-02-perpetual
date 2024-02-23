// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./VaultSpecSetup.sol";

// TODO test using collateral token w diff decimals
contract TransferFundToMargin is VaultSpecSetup {
    address public taker = makeAddr("taker");

    function setUp() public virtual override {
        super.setUp();
        _deposit(taker, 10 ether);
    }

    function test_TransferFundToMargin() public {
        vm.prank(taker);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.MarginChanged(marketId, taker, 1 ether);

        vault.transferFundToMargin(marketId, 1 ether);
        assertEq(_getPosition(marketId, taker).margin, 1 ether);
    }

    function test_RevertIf_InvalidMarketId() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidMarket.selector, 2 ether));
        vault.transferFundToMargin(2 ether, 1 ether);
    }
}
