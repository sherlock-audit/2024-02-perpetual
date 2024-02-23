// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

library LibFormatter {
    function formatDecimals(uint256 num, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return num;
        }
        return
            fromDecimals >= toDecimals
                ? num / 10 ** (fromDecimals - toDecimals)
                : num * 10 ** (toDecimals - fromDecimals);
    }

    // copied from SettlementTokenMath.convertTokenDecimals()
    function formatDecimals(int256 num, uint8 fromDecimals, uint8 toDecimals) internal pure returns (int256) {
        if (fromDecimals == toDecimals) {
            return num;
        }

        if (fromDecimals < toDecimals) {
            return num * int256(10 ** (toDecimals - fromDecimals));
        }

        // round down, ex: -3.5 => -4, 3.5 => 3
        uint256 denominator = 10 ** (fromDecimals - toDecimals);
        int256 rounding = 0;
        if (num < 0 && uint256(-num) % denominator != 0) {
            rounding = -1;
        }
        return num / int256(denominator) + rounding;
    }
}
