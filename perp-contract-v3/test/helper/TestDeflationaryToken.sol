// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestDeflationaryToken is ERC20 {
    uint256 public fee; // in decimal 2

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        fee = 1;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool success) {
        if (fee != 0) {
            _burn(sender, fee);
            amount = amount - fee;
        }
        return super.transferFrom(sender, recipient, amount);
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
