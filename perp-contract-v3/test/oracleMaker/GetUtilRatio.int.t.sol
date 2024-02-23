// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { OracleMakerIntSetup } from "./OracleMakerIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract OracleMakerGetUtilRatioInt is OracleMakerIntSetup {
    address public lp = makeAddr("LiquidityProvider");
    address public taker = makeAddr("Taker");

    function setUp() public virtual override {
        super.setUp();
        maker.setValidSender(taker, true);

        // lp deposit 10000 to maker
        uint256 makerAmount = 10000e6;
        deal(address(collateralToken), lp, makerAmount, true);
        vm.startPrank(lp);
        collateralToken.approve(address(maker), makerAmount);
        maker.deposit(makerAmount);
        vm.stopPrank();

        // taker deposit 1000
        _deposit(marketId, taker, 1000e6);

        _mockPythPrice(1000, 0);
    }

    function test_util_ratio_should_be_0_when_no_position() public {
        (uint256 longUtilRatio, uint256 shortUtilRatio) = maker.getUtilRatio();
        assertEq(longUtilRatio, 0);
        assertEq(shortUtilRatio, 0);
    }

    function test_long_util_ratio_should_gt_0_when_taker_long() public {
        // taker long 1 eth
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // maker max position notional = 10000 usdc
        // maker position size = -1 eth
        // maker position rate = -0.1
        (uint256 longUtilRatio, uint256 shortUtilRatio) = maker.getUtilRatio();
        assertEq(longUtilRatio, 0.1e18);
        assertEq(shortUtilRatio, 0);
    }

    function test_short_util_ratio_should_gt_0_when_taker_short() public {
        // taker short 3 eth
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 3 ether,
                oppositeAmountBound: 3000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // maker max position notional = 10000 usdc
        // maker position size = 3 eth
        // maker position rate = 0.3
        (uint256 longUtilRatio, uint256 shortUtilRatio) = maker.getUtilRatio();
        assertEq(longUtilRatio, 0);
        assertEq(shortUtilRatio, 0.3e18);
    }
}
