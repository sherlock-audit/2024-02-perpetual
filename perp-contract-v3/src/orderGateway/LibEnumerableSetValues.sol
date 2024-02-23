// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library LibEnumerableSetValues {
    using EnumerableSet for EnumerableSet.UintSet;

    // copy from https://github.com/gmx-io/gmx-synthetics/blob/0e0091f9d0180004d956f5ea23cc3aceaf60433e/contracts/utils/EnumerableValues.sol
    function valuesAt(
        EnumerableSet.UintSet storage set,
        uint256 start,
        uint256 end
    ) internal view returns (uint256[] memory) {
        if (start >= set.length()) {
            return new uint256[](0);
        }

        uint256 max = set.length();
        if (end > max) {
            end = max;
        }

        uint256[] memory items = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            items[i - start] = set.at(i);
        }

        return items;
    }
}
