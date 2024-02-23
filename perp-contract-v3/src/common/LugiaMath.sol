// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

library LibLugiaMath {
    function applyDelta(uint256 a, int256 delta) internal pure returns (uint256) {
        // skip the check for delta == min(int256) because it wont' happen in our case
        if (delta < 0) {
            return a - uint256(-delta);
        } else {
            return a + uint256(delta);
        }
    }
}
