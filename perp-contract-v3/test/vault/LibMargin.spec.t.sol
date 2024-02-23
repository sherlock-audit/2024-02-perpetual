// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../../src/vault/LibMargin.sol";

contract LibMarginSpec is Test {
    function test_FreeMargin_PnlPoolNotEnoughForUnsettledProfit() external {
        // when margin state = 1, pending margin = 0, unsettled profit = 2, pnl pool = 1
        assertEq(LibMargin.getFreeMargin(1, 0, 2, 1), 2);
    }

    function test_FreeMargin_PnlPoolNotEnoughForPositivePendingMargin() external {
        // when margin state = 1, pending margin = 2, unsettled profit = 0, pnl pool = 1
        assertEq(LibMargin.getFreeMargin(1, 2, 0, 1), 2);
    }

    function test_FreeMargin_PnlPoolEnoughForUnsettledProfit() external {
        // when margin state = 1, unsettled profit = 2, pnl pool = 2
        assertEq(LibMargin.getFreeMargin(1, 0, 2, 2), 3);
    }

    function test_FreeMargin_MarginNotEnoughForUnsettledLoss() external {
        // when margin state = 1, unsettled profit = -2
        assertEq(LibMargin.getFreeMargin(1, 0, -2, 0), 0);
    }

    function test_FreeMargin_MarginNotEnoughForUnsettledLoss_NegativePendingMargin() external {
        // when margin state = 2, unsettled profit = -1, pending margin = -3
        assertEq(LibMargin.getFreeMargin(2, -1, -3, 0), 0);
    }

    function test_FreeMargin_MarginEnoughForUnsettledLoss() external {
        // when margin state = 2, unsettled profit = -1
        assertEq(LibMargin.getFreeMargin(2, -1, 0, 0), 1);
    }
}
