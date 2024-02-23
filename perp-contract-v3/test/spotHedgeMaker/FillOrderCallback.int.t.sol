// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { SpotHedgeBaseMakerIntSetup } from "./SpotHedgeBaseMakerIntSetup.sol";

contract SpotHedgeBaseMakerFillOrderCallbackInt is SpotHedgeBaseMakerIntSetup {
    function setUp() public virtual override {
        SpotHedgeBaseMakerIntSetup.setUp();
        _provisionMakerForFillOrder();
        _mockPythPrice(150, 0);
    }

    function testFuzz_fillOrderCallback_B2Q_exactInput_Normal(uint256 baseAmount, uint256 quoteAmount) public {
        // Fuzz test and assume:
        // - Nothing since B2Q swaps does not utilize fillOrderCallback

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.prank(address(clearingHouse));
        maker.fillOrderCallback(
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: true,
                    isExactInput: true,
                    amountXSpotDecimals: baseAmount,
                    oppositeAmountXSpotDecimals: quoteAmount
                })
            )
        );

        // No swaps should happen.
        assertEq(baseToken.balanceOf(address(maker)), makerBaseBalanceBefore);
        assertEq(collateralToken.balanceOf(address(vault)), vaultCollateralBalanceBefore);
    }

    function testFuzz_fillOrderCallback_Q2B_exactInput_Normal(uint256 baseAmount, uint256 quoteAmount) public {
        // Fuzz test and assume:
        // - The swap amount never exceeds maker's balances
        // - No zero amounts
        vm.assume(baseAmount > 0 && baseAmount < 1e36);
        vm.assume(quoteAmount > 0 && quoteAmount < 1e36);

        // Fake uniswap router behavior.
        uniswapV3Router.setAmountOut(
            ISwapRouter.ExactInputParams({
                path: uniswapV3Q2BPath,
                recipient: address(maker),
                deadline: block.timestamp,
                amountIn: quoteAmount,
                amountOutMinimum: baseAmount
            }),
            baseAmount
        );

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.prank(address(clearingHouse));
        maker.fillOrderCallback(
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: false,
                    isExactInput: true,
                    amountXSpotDecimals: quoteAmount,
                    oppositeAmountXSpotDecimals: baseAmount
                })
            )
        );

        // Maker should withdraw its USDC for swap.
        uint256 vaultCollateralBalanceAfter = collateralToken.balanceOf(address(vault));
        assertEq(vaultCollateralBalanceAfter, vaultCollateralBalanceBefore - quoteAmount);

        // Maker should acquired ETH.
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(address(maker));
        assertEq(makerBaseBalanceAfter, makerBaseBalanceBefore + baseAmount);
    }

    function testFuzz_fillOrderCallback_B2Q_exactOutput_Normal(uint256 baseAmount, uint256 quoteAmount) public {
        // Fuzz test and assume:
        // - Nothing since B2Q swaps does not utilize fillOrderCallback

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.prank(address(clearingHouse));
        maker.fillOrderCallback(
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: true,
                    isExactInput: false,
                    amountXSpotDecimals: quoteAmount,
                    oppositeAmountXSpotDecimals: baseAmount
                })
            )
        );

        // No swaps should happen.
        assertEq(baseToken.balanceOf(address(maker)), makerBaseBalanceBefore);
        assertEq(collateralToken.balanceOf(address(vault)), vaultCollateralBalanceBefore);
    }

    function testFuzz_fillOrderCallback_Q2B_exactOutput_Normal(uint256 baseAmount, uint256 quoteAmount) public {
        // Fuzz test and assume:
        // - The swap amount never exceeds maker's balances
        // - No zero amounts
        vm.assume(baseAmount > 0 && baseAmount < 1e36);
        vm.assume(quoteAmount > 0 && quoteAmount < 1e36);

        // Fake uniswap router behavior.
        uniswapV3Router.setAmountIn(
            ISwapRouter.ExactOutputParams({
                path: uniswapV3B2QPath, // Paths are inverted when expectOutput
                recipient: address(maker),
                deadline: block.timestamp,
                amountOut: baseAmount,
                amountInMaximum: quoteAmount
            }),
            quoteAmount
        );

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.prank(address(clearingHouse));
        maker.fillOrderCallback(
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: false,
                    isExactInput: false,
                    amountXSpotDecimals: baseAmount,
                    oppositeAmountXSpotDecimals: quoteAmount
                })
            )
        );

        // Maker should withdraw its USDC for swap.
        uint256 vaultCollateralBalanceAfter = collateralToken.balanceOf(address(vault));
        assertEq(vaultCollateralBalanceAfter, vaultCollateralBalanceBefore - quoteAmount);

        // Maker should acquired ETH.
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(address(maker));
        assertEq(makerBaseBalanceAfter, makerBaseBalanceBefore + baseAmount);
    }
}
