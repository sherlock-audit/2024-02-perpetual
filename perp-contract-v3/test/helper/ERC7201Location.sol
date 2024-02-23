// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

contract ERC7201Location {
    // adding 2 as suffix is to prevent function become diamond inheritance
    function test_excludeFromCoverageReport2() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function getLocation(string memory domain) public pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(domain))) - 1)) & ~bytes32(uint256(0xff));
    }
}
