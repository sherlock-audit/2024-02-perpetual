// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../src/vault/IPositionModelEvent.sol";
import "../../src/vault/LibPositionModel.sol";
import "../BaseTest.sol";
import "./LibPositionModelHarness.sol";

contract SettlePnlSpec is BaseTest {
    uint256 public marketId = 0;
    address public taker = makeAddr("taker");
    address public maker = makeAddr("maker");
    LibPositionModelHarness public libHarness;

    // Tested cases using the external `settlePnl()`:
    //    pnlToSettle       unsettledPnl     pnlToSettle > pnlPool       expect
    //          >0              >0                 y                       emit & state changes
    //          >0              >0                 n                       emit & state changes
    //           0               0                 n                       no emits & no state changes

    // Tested cases using the exposed harness `exposed_settlePnl()`:
    //       realizedPnl     unsettledPnl     pnlToSettle   margin < -pnlToSettle   pnlToSettle > pnlPool  expect
    //          <0              >0                0                n                          n            emit & state changes except pnl pool
    //          >0              >0               >0                n                          y            emit & state changes
    //          >0              >0               >0                n                          n            emit & state changes
    //          <0              >0               >0                n                          y            emit & state changes
    //          <0              >0               >0                n                          n            emit & state changes
    //          >0              <0               >0                n                          y            emit & state changes
    //          >0              <0               >0                n                          n            emit & state changes
    //-------------------------------------------------------------------------------------------------------------------------------------------
    //          <0              <0               <0                y                          n            emit & state changes
    //          <0              <0               <0                n                          n            emit & state changes
    //          >0              <0               <0                y                          n            emit & state changes
    //          >0              <0               <0                n                          n            emit & state changes
    //          <0              >0               <0                y                          n            emit & state changes
    //          <0              >0               <0                n                          n            emit & state changes

    function setUp() public {
        libHarness = new LibPositionModelHarness();
    }

    function test_PositiveSettlementGreaterThanPnlPoolZeroRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   unsettlePnl = 100 - 60 = 40
        //   margin = 100 + 60 = 160
        // pnlPool = 60 - 60 = 0
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 0), 60);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 40);
        assertEq(libHarness.getPnlPoolBalance(marketId), 0);
    }

    function test_PositiveSettlementSmallerThanPnlPoolZeroRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        // pnlPool = 120
        libHarness.exposed_setPnlPoolBalance(marketId, 120);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   margin = 100 + 100 = 200
        //   unsettlePnl = 100 - 100 = 0
        // pnlPool = 120 - 100 = 20
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 0), 100);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 20);
    }

    function test_ZeroUnsettledPnlZeroRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 0
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            0 // unsettledPnl
        );

        // Expect nothing changes
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 0), 0);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 60);
    }

    function test_PositiveSettlementGreaterThanPnlPoolPositiveRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        //   realizedPnl = 10
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   unsettlePnl = 100 + 10 - 60 = 50
        //   margin = 100 + 60 = 160
        // pnlPool = 60 - 60 = 0
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 10), 60);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 50);
        assertEq(libHarness.getPnlPoolBalance(marketId), 0);
    }

    function test_PositiveSettlementGreaterThanPnlPoolNegativeRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        //   realizedPnl = -10
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   unsettlePnl = 100 - 10 - 60 = 30
        //   margin = 100 + 60 = 160
        // pnlPool = 60 - 60 = 0
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -10), 60);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 30);
        assertEq(libHarness.getPnlPoolBalance(marketId), 0);
    }

    function test_PositiveSettlementSmallerThanPnlPoolPositiveRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        //   realizedPnl = 10
        // pnlPool = 130
        libHarness.exposed_setPnlPoolBalance(marketId, 130);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   margin = 100 + 100 + 10 = 210
        //   unsettlePnl = 100 + 10 - 110 = 0
        // pnlPool = 130 - 110 = 20
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 10), 110);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 20);
    }

    function test_PositiveSettlementSmallerThanPnlPoolNegativeRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        //   realizedPnl = -10
        // pnlPool = 130
        libHarness.exposed_setPnlPoolBalance(marketId, 130);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   margin = 100 + 100 - 10 = 190
        //   unsettlePnl = 100 - 10 - 90 = 0
        // pnlPool = 130 - 90 = 40
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -10), 90);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 40);
    }

    function test_ZeroSettlementPositiveRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = -100
        //   realizedPnl = 100
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            -100 // unsettledPnl
        );
        libHarness.exposed_setBadDebt(marketId, 100);
        // taker:
        //   margin = 100 + 100 - 100 = 100
        //   unsettlePnl = 100 - 100 = 0
        // pnlPool = 60 - 0 = 60
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 100), 0);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 60);
    }

    function test_ZeroSettlementNegativeRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 100
        //   realizedPnl = -100
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            100 // unsettledPnl
        );
        // taker:
        //   margin = 100 + 100 - 100 = 100
        //   unsettlePnl = 100 - 100 = 0
        // pnlPool = 60 - 0 = 60
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -100), 0);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 60);
    }

    function test_NegativeSettlementSmallerThanMarginNegativeRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = 10
        //   realizedPnl = -30
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            10 // unsettledPnl
        );
        // taker:
        //   margin = 100 + 10 - 30 = 80
        //   unsettlePnl = 10 - 10 = 0
        // pnlPool = 60 - 10 + 30 = 80
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -30), -20);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 80);
    }

    function test_NegativeSettlementGreaterThanMarginNegativeRealizedPnl_() public {
        // taker:
        //   margin = 10
        //   unsettlePnl = 10
        //   realizedPnl = -30
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            10, // margin
            10 // unsettledPnl
        );
        // taker:
        //   pnlToSettle = 10 + (-30) = -20
        //   settlePnl = -min(10, 20) = -10 (pay to pnlPool)
        //   unsettlePnl = -20 - (-10) = -10 (debt)
        //   margin = 10 - 10 = 0
        // pnlPool = 60 + 10 = 70
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -30), -10);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), -10);
        assertEq(libHarness.getPnlPoolBalance(marketId), 70);
    }

    function test_NegativeSettlementSmallerThanMarginPositiveRealizedPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = -30
        //   realizedPnl = 10
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            -30 // unsettledPnl
        );
        libHarness.exposed_setBadDebt(marketId, 30);
        // taker:
        //   margin = 100 + 10 - 30 = 80
        //   unsettlePnl = 10 - 10 = 0
        // pnlPool = 60 - 10 + 30 = 80
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 10), -20);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 80);
    }

    function test_NegativeSettlementGreaterThanMarginPositiveRealizedPnl() public {
        // taker:
        //   margin = 10
        //   unsettlePnl = -30
        //   realizedPnl = 10
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            10, // margin
            -30 // unsettledPnl
        );
        libHarness.exposed_setBadDebt(marketId, 30);
        // taker:
        //   pnlToSettle = 10 + (-30) = -20
        //   settlePnl = -min(10, 20) = -10 (pay to pnlPool)
        //   unsettlePnl = -20 - (-10) = -10 (debt)
        //   margin = 10 - 10 = 0
        // pnlPool = 60 + 10 = 70
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 10), -10);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), -10);
        assertEq(libHarness.getPnlPoolBalance(marketId), 70);
    }

    function test_NegativeSettlementSmallerThanMarginNegativeRealizedPnlNegativeUnsettledPnl() public {
        // taker:
        //   margin = 100
        //   unsettlePnl = -20
        //   realizedPnl = -30
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            100, // margin
            -20 // unsettledPnl
        );
        libHarness.exposed_setBadDebt(marketId, 20);
        // taker:
        //   pnlToSettle = -20 + (-30) = -50
        //   settlePnl = -min(100, 50) = -50 (pay to pnlPool)
        //   unsettlePnl = -50 - (-50) = 0 (debt)
        //   margin = 100 - 50 = 50
        // pnlPool = 60 + 50 = 110
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -30), -50);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 110);
    }

    function test_NegativeSettlementGreaterThanMarginNegativeRealizedPnlNegativeUnsettledPnl() public {
        // taker:
        //   margin = 10
        //   unsettlePnl = -20
        //   realizedPnl = -30
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            10, // margin
            -20 // unsettledPnl
        );
        // taker:
        //   pnlToSettle = -20 + (-30) = -50
        //   settlePnl = -min(10, 50) = -10 (pay to pnlPool)
        //   unsettlePnl = -50 - (-10) = -40 (debt)
        //   margin = 10 - 10 = 0
        // pnlPool = 60 + 10 = 70
        assertEq(libHarness.exposed_settlePnl(marketId, taker, -30), -10);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), -40);
        assertEq(libHarness.getPnlPoolBalance(marketId), 70);
    }

    function test_NegativeSettlementGreaterThanMarginWithZeroMargin() public {
        // taker:
        //   margin = 0
        //   unsettlePnl = -20
        //   realizedPnl = 10
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            0, // margin
            -20 // unsettledPnl
        );
        libHarness.exposed_setBadDebt(marketId, 20);
        // taker:
        //   pnlToSettle = -20 + (10) = -10
        //   settlePnl = -min(0, 10) = 0 (pay to pnlPool)
        //   unsettlePnl = -20 - (-10) = -10 (debt)
        //   margin = 0
        // pnlPool = 60
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 10), 0);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), -10);
        assertEq(libHarness.getPnlPoolBalance(marketId), 60);
    }

    function test_NegativeSettlementEqualToMarginAddRealizedPnl() public {
        // taker:
        //   margin = 5
        //   unsettlePnl = -20
        //   realizedPnl = 15
        // pnlPool = 60
        libHarness.exposed_setPnlPoolBalance(marketId, 60);
        libHarness.exposed_setMarginAndUnsettledPnl(
            marketId,
            taker,
            5, // margin
            -20 // unsettledPnl
        );
        libHarness.exposed_setBadDebt(marketId, 20);
        // taker:
        //   pnlToSettle = -20 + (15) = -5
        //   settlePnl = -min(5, 5) = -5 (pay to pnlPool)
        //   unsettlePnl = -5 - (-5) = 0 (debt)
        //   margin = 5 + (-5) = 0
        // pnlPool = 60 + 5 = 65
        assertEq(libHarness.exposed_settlePnl(marketId, taker, 15), -5);
        assertEq(libHarness.getUnsettledPnl(marketId, taker), 0);
        assertEq(libHarness.getPnlPoolBalance(marketId), 65);
    }
}
