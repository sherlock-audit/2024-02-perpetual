// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/StdInvariant.sol";
import "../clearingHouse/ClearingHouseIntSetup.sol";
import { PnlPoolHandler } from "./PnlPoolHandler.sol";

contract PnlPoolInvariantTest is ClearingHouseIntSetup {
    PnlPoolHandler public handler;

    function setUp() public virtual override {
        super.setUp();

        TestMaker maker1 = _newMarketWithTestMaker(marketId);
        TestMaker maker2 = new TestMaker(vault);
        config.registerMaker(marketId, address(maker2));

        address[] memory makerList = new address[](2);
        makerList[0] = address(maker1);
        makerList[1] = address(maker2);
        handler = new PnlPoolHandler(vault, clearingHouse, address(pyth), priceFeedId, marketId, makerList);

        targetContract(address(handler));

        bytes4[] memory fuzzSelectors = new bytes4[](1);
        fuzzSelectors[0] = PnlPoolHandler.tradeWithWhitelistedMaker.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: fuzzSelectors }));
    }

    function invariant_sumRealMargin() public {
        // Calculate current total margin
        uint256 sumInternalMargin = 0;
        for (uint256 i = 0; i < handler.getTraderSetLength(); i++) {
            address trader = handler.getTraderAtIndex(i);
            int256 internalMargin = vault.getSettledMargin(marketId, trader) - vault.getUnsettledPnl(marketId, trader);
            require(internalMargin >= 0, "Unexpected negative margin");
            sumInternalMargin += uint256(internalMargin);
        }

        uint256 pnlPoolBalance = vault.getPnlPoolBalance(marketId);

        // Assuming no borrowing fee and no funding fee
        // total margin (margin + trader_unsettledMargin + PnlPoolBalance) should remain constant
        assertEq(handler.sumInitialMargin(), sumInternalMargin + pnlPoolBalance);
    }
}
