// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Quoter } from "../../src/quoter/Quoter.sol";
import { TestMaker } from "../helper/TestMaker.sol";
import "../clearingHouse/ClearingHouseIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract FakeClearingHouse {
    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function quoteOpenPosition(IClearingHouse.OpenPositionParams calldata) external pure returns (int256, int256) {
        revert("test error");
    }
}

contract QuoteInt is ClearingHouseIntSetup {
    TestMaker public maker;
    Quoter public quoter;

    function setUp() public override {
        super.setUp();
        quoter = new Quoter(address(addressManager));

        maker = _newMarketWithTestMaker(marketId);
        maker.setBaseToQuotePrice(150e18);
        _mockPythPrice(150, 0);

        _deposit(marketId, address(maker), 10000e6);
        // 0.00000001 per second
        config.setMaxBorrowingFeeRate(marketId, 10000000000, 10000000000);
    }

    function test_quote() public {
        (int256 base, int256 quote) = quoter.quote(
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
        assertEq(base, -10 ether);
        assertEq(quote, 1500 ether);
    }

    function test_RevertIf_RevertsWithString() public {
        addressManager.setAddress(CLEARING_HOUSE, address(new FakeClearingHouse()));

        vm.expectRevert("test error");
        quoter.quote(
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
}
