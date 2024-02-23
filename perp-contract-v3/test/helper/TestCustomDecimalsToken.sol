// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestCustomDecimalsToken is ERC20 {
    uint8 _decimals;

    constructor(string memory nameArg, string memory symbolArg, uint8 decimalsArg) ERC20(nameArg, symbolArg) {
        _decimals = decimalsArg;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function test_excludeFromCoverageReport() public {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
