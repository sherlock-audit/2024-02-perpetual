// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IQuoter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/IQuoter.sol";
import { Path } from "../../src/external/uniswap-v3-periphery/contracts/libraries/Path.sol";

contract FakeUniswapV3Quoter is Test {
    using Path for bytes;

    bytes internal _path;
    uint256 internal _amountIn;
    uint256 internal _amountOut;

    function setAmountOut(bytes memory path, uint256 amountIn, uint256 amountOut) external {
        _path = path;
        _amountIn = amountIn;
        _amountOut = amountOut;
    }

    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut) {
        assertEq(path, _path);
        assertEq(amountIn, _amountIn);
        return _amountOut;
    }

    function setAmountIn(bytes memory path, uint256 amountOut, uint256 amountIn) external {
        _path = path;
        _amountIn = amountIn;
        _amountOut = amountOut;
    }

    function quoteExactOutput(bytes memory path, uint256 amountOut) external returns (uint256 amountIn) {
        assertEq(path, _path);
        assertEq(amountOut, _amountOut);
        return _amountIn;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
