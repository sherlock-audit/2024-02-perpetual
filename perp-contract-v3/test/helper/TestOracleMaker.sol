// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { OracleMaker } from "../../src/maker/OracleMaker.sol";

contract TestOracleMaker is OracleMaker {
    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function getBasePriceWithSpread(uint256 basePrice, bool isBaseToQuote) public view returns (uint256) {
        return _getBasePriceWithSpread(basePrice, isBaseToQuote);
    }

    function getPositionRate(uint256 basePrice) public view returns (int256) {
        return _getPositionRate(basePrice);
    }
}
