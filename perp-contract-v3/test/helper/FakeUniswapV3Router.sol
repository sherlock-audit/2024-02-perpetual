// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { Path } from "../../src/external/uniswap-v3-periphery/contracts/libraries/Path.sol";

contract FakeUniswapV3Router is Test {
    using SafeERC20 for IERC20Metadata;
    using Path for bytes;

    ISwapRouter.ExactInputParams internal _exactInputParams;
    ISwapRouter.ExactOutputParams internal _exectOutputParams;
    uint256 internal _amountOut;
    uint256 internal _amountIn;

    function setAmountOut(ISwapRouter.ExactInputParams calldata params, uint256 value) external {
        _exactInputParams = params;
        _amountOut = value;
    }

    function exactInput(ISwapRouter.ExactInputParams memory params) external returns (uint256 amountOut) {
        _assertExactInputEq(_exactInputParams, params);

        (address tokenIn, , ) = params.path.decodeFirstPool();
        IERC20Metadata(tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();
            // decide whether to continue or terminate
            if (hasMultiplePools) {
                params.path = params.path.skipToken();
            } else {
                (, address tokenOut, ) = params.path.decodeFirstPool();
                amountOut = _amountOut;
                IERC20Metadata(tokenOut).safeTransfer(params.recipient, amountOut);
                break;
            }
        }
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    function setAmountIn(ISwapRouter.ExactOutputParams calldata params, uint256 value) external {
        _exectOutputParams = params;
        _amountIn = value;
    }

    function exactOutput(ISwapRouter.ExactOutputParams memory params) external returns (uint256 amountIn) {
        _assertExactOutputEq(_exectOutputParams, params);

        (address tokenOut, , ) = params.path.decodeFirstPool();
        IERC20Metadata(tokenOut).safeTransfer(params.recipient, params.amountOut);

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();
            // decide whether to continue or terminate
            if (hasMultiplePools) {
                params.path = params.path.skipToken();
            } else {
                (, address tokenIn, ) = params.path.decodeFirstPool();
                amountIn = _amountIn;
                IERC20Metadata(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
                break;
            }
        }
        require(amountIn <= params.amountInMaximum, "Too much requested");
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function _assertExactInputEq(
        ISwapRouter.ExactInputParams memory a,
        ISwapRouter.ExactInputParams memory b
    ) internal {
        assertEq(a.path, b.path);
        assertEq(a.recipient, b.recipient);
        assertEq(a.amountIn, b.amountIn);
        assertEq(a.amountOutMinimum, b.amountOutMinimum);
    }

    function _assertExactOutputEq(
        ISwapRouter.ExactOutputParams memory a,
        ISwapRouter.ExactOutputParams memory b
    ) internal {
        assertEq(a.path, b.path);
        assertEq(a.recipient, b.recipient);
        assertEq(a.amountOut, b.amountOut);
        assertEq(a.amountInMaximum, b.amountInMaximum);
    }
}
