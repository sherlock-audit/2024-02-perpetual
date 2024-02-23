// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { SpotHedgeBaseMakerSpecSetup } from "./SpotHedgeBaseMakerSpecSetup.sol";

contract GetUtilRatioTest is SpotHedgeBaseMakerSpecSetup {
    SpotHedgeBaseMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        SpotHedgeBaseMakerSpecSetup.setUp();

        maker = _create_Maker();
    }

    function test_getUtilRatio() public {
        (, uint256 shortUtilRatio) = maker.getUtilRatio();
        assertEq(shortUtilRatio, 0);

        uint256 depositAmount = 10e9;
        deal(address(baseToken), lp, depositAmount, true);

        vm.startPrank(lp);
        baseToken.approve(address(maker), depositAmount);
        maker.deposit(depositAmount);

        // First getUtilRatio() should pass
        (, uint256 firstShortUtilRatio) = maker.getUtilRatio();
        assertEq(firstShortUtilRatio, 0);

        // Second getUtilRatio() should pass as long as getUtilRatio() handles the edge cases when
        // the maker receives unexpected inflow of base tokens.
        deal(address(baseToken), address(maker), 20e9, true);
        (, uint256 secondShortUtilRatio) = maker.getUtilRatio();
        assertEq(secondShortUtilRatio, 0);
    }
}
