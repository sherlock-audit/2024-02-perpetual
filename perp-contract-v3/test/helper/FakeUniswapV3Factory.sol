// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

contract FakeUniswapV3Factory {
    mapping(bytes32 => address) internal _uniswapV3PoolMap;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        _uniswapV3PoolMap[_getKey(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool) {
        return _uniswapV3PoolMap[_getKey(tokenA, tokenB, fee)];
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function _getKey(address tokenIn, address tokenOut, uint24 fee) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut, fee));
    }
}
