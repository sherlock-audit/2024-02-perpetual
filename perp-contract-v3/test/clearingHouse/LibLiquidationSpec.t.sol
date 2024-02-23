// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import "../../src/clearingHouse/LibLiquidation.sol";

contract LiquidateSpec is Test {
    using SafeCast for uint256;
    using SafeCast for int256;
    using FixedPointMathLib for int256;
    using LibLiquidation for MaintenanceMarginProfile;

    function testFuzz_liquidate(
        uint256 price,
        uint256 positionSizeAbs,
        uint256 openNotionalAbs,
        bool isLong,
        int256 accountValue,
        uint256 maintenanceMarginRequirement,
        uint256 liquidationPenaltyRatio
    ) public {
        // Avoid overflow in unreasonable edge cases since we will do "positionSize * price.toInt256()"
        price = bound(price, 1, 1000000e18);
        positionSizeAbs = bound(positionSizeAbs, 1, type(uint64).max);
        openNotionalAbs = bound(openNotionalAbs, 1, type(uint64).max);
        accountValue = bound(accountValue, -type(int64).max, type(int64).max);
        liquidationPenaltyRatio = bound(liquidationPenaltyRatio, 0, 1 ether);
        maintenanceMarginRequirement = bound(maintenanceMarginRequirement, accountValue.abs() + 1, type(uint64).max);
        int256 positionSize = isLong ? positionSizeAbs.toInt256() : -positionSizeAbs.toInt256();
        int256 openNotional = isLong ? -openNotionalAbs.toInt256() : openNotionalAbs.toInt256();

        console.log("price", price);
        console.log("positionSize");
        console.logInt(positionSize);
        console.log("openNotional");
        console.logInt(openNotional);
        console.log("accountValue");
        console.logInt(accountValue);
        console.log("maintenanceMarginRequirement", maintenanceMarginRequirement);
        console.log("liquidationPenaltyRatio", liquidationPenaltyRatio);

        MaintenanceMarginProfile memory profile = MaintenanceMarginProfile({
            price: price,
            positionSize: positionSize,
            openNotional: openNotional,
            accountValue: accountValue,
            maintenanceMarginRequirement: maintenanceMarginRequirement.toInt256(),
            liquidationPenaltyRatio: liquidationPenaltyRatio,
            liquidationFeeRatio: 0
        });
        int256 liquidatedPositionSize = profile.getLiquidatablePositionSize();
        LiquidationResult memory result = profile.getLiquidationResult(liquidatedPositionSize.abs());

        int256 liquidatedPositionSizeDelta = -liquidatedPositionSize;
        int256 liquidatedPositionNotionalDelta = (liquidatedPositionSize * price.toInt256()) / 1e18;
        uint256 liquidatedNotionalMulWad = openNotionalAbs * liquidatedPositionSizeDelta.abs();
        uint256 penalty = (liquidatedNotionalMulWad * liquidationPenaltyRatio) / positionSizeAbs / WAD;

        assertEq(result.liquidatedPositionSizeDelta, liquidatedPositionSizeDelta, "liquidatedPositionSizeDelta");
        assertEq(
            result.liquidatedPositionNotionalDelta,
            liquidatedPositionNotionalDelta,
            "liquidatedPositionNotionalDelta"
        );
        assertEq(penalty, result.penalty, "penalty");
    }
}
