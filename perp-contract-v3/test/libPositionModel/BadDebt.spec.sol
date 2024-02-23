// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../src/vault/IPositionModelEvent.sol";
import "../../src/vault/LibPositionModel.sol";
import "../BaseTest.sol";
import "./LibPositionModelHarness.sol";

contract SettlePnlSpec is BaseTest {
    uint256 public marketId = 0;
    LibPositionModelHarness public libHarness;

    function setUp() public {
        libHarness = new LibPositionModelHarness();
    }

    function test_BadDebtCalculation() public {
        // someone has 10 unsettledPnl, after settlement it's -40. increasing 40 bad debt
        assertEq(libHarness.exposed_updateBadDebt(marketId, 10, -40), 40);
        assertEq(libHarness.getBadDebt(marketId), 40);

        // someone has 0 unsettledPnl, after settlement it's -70. increasing 70 bad debt
        assertEq(libHarness.exposed_updateBadDebt(marketId, 0, -70), 70);
        assertEq(libHarness.getBadDebt(marketId), 40 + 70);

        // someone has -40 unsettledPnl, after settlement it's -30. decreasing 10 bad debt
        assertEq(libHarness.exposed_updateBadDebt(marketId, -40, -30), -10);
        assertEq(libHarness.getBadDebt(marketId), 40 + 70 - 10);

        // someone has -30 unsettledPnl, after settlement it's 0. decreasing 30 bad debt
        assertEq(libHarness.exposed_updateBadDebt(marketId, -30, 0), -30);
        assertEq(libHarness.getBadDebt(marketId), 40 + 70 - 10 - 30);
    }
}
