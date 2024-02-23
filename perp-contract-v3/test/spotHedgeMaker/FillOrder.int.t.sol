// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { SpotHedgeBaseMakerIntSetup } from "./SpotHedgeBaseMakerIntSetup.sol";

contract SpotHedgeBaseMakerFillOrderInt is SpotHedgeBaseMakerIntSetup {
    function setUp() public virtual override {
        SpotHedgeBaseMakerIntSetup.setUp();
        _provisionMakerForFillOrder();
        _mockPythPrice(150, 0);
    }

    function testFuzz_fillOrder_B2Q_exactInput_Normal(uint256 baseAmount) public {
        // Fuzz test and assume:
        // - There will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        // - Minimum amount of 1e10 or otherwise spotQuoteAmount will be zero
        vm.assume(baseAmount > 1e10 && baseAmount < 1e36);

        // perpBaseAmount: 18-decimal
        // perpQuoteAmount: 18-decimal
        // spotBaseAmount: 9-decimal
        // spotQuoteAmount: 6-decimal

        // Price = $100
        uint256 spotBaseAmount = baseAmount / 10 ** (18 - 9); // Convert from 18-decimal to 9-decimal
        uint256 spotQuoteAmount = (baseAmount * 100) / 10 ** (18 - 6); // Convert from 18-decimal to 6-decimal
        uint256 expectedQuoteAmount = spotQuoteAmount * 10 ** (18 - 6); // Convert from 6-decimal to 18-decimal

        // Fake uniswap router behavior.
        uniswapV3Router.setAmountOut(
            ISwapRouter.ExactInputParams({
                path: uniswapV3B2QPath,
                recipient: address(maker),
                deadline: block.timestamp,
                amountIn: spotBaseAmount,
                amountOutMinimum: 0
            }),
            spotQuoteAmount
        );

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.SHMOrderFilled(
            marketId,
            uniswapV3B2QPath, // path
            true, // isBaseToQuote
            true, // isExactInput
            baseAmount, // targetAmount
            expectedQuoteAmount, // oppositeAmount,
            0 // spread
        );
        vm.prank(address(clearingHouse));
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            true, // isBaseToQuote
            true, // isExactInput
            baseAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedQuoteAmount, 18);
        assertEq(
            callbackData,
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: true,
                    isExactInput: true,
                    amountXSpotDecimals: spotBaseAmount,
                    oppositeAmountXSpotDecimals: spotQuoteAmount
                })
            )
        );

        // Maker should swap out its ETH.
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(address(maker));
        assertEq(makerBaseBalanceAfter, makerBaseBalanceBefore - spotBaseAmount);

        // Maker should deposit the USDC acquired to vault.
        uint256 vaultCollateralBalanceAfter = collateralToken.balanceOf(address(vault));
        assertEq(vaultCollateralBalanceAfter, vaultCollateralBalanceBefore + spotQuoteAmount);
    }

    function testFuzz_fillOrder_Q2B_exactInput_Normal(uint256 quoteAmount) public {
        // Fuzz test and assume:
        // - There will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        // - Minimum amount of 1e12 or otherwise spotQuoteAmount will be zero
        vm.assume(quoteAmount > 1e12 && quoteAmount < 1e36);

        // perpBaseAmount: 18-decimal
        // perpQuoteAmount: 18-decimal
        // spotBaseAmount: 9-decimal
        // spotQuoteAmount: 6-decimal

        // Price = $100
        uint256 spotBaseAmount = quoteAmount / 100 / 10 ** (18 - 9); // Convert from 18-decimal to 9-decimal
        uint256 spotQuoteAmount = quoteAmount / 10 ** (18 - 6); // Convert from 18-decimal to 6-decimal
        uint256 expectedBaseAmount = spotBaseAmount * 10 ** (18 - 9); // Convert from 9-decimal to 18-decimal

        // Fake uniswap quoter behavior.
        uniswapV3Quoter.setAmountOut(uniswapV3Q2BPath, spotQuoteAmount, spotBaseAmount);

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.SHMOrderFilled(
            marketId,
            uniswapV3Q2BPath, // path
            false, // isBaseToQuote
            true, // isExactInput
            quoteAmount, // targetAmount
            expectedBaseAmount, // oppositeAmount,
            0 // spread
        );
        vm.prank(address(clearingHouse));
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            false, // isBaseToQuote
            true, // isExactInput
            quoteAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedBaseAmount, 18);
        assertEq(
            callbackData,
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: false,
                    isExactInput: true,
                    amountXSpotDecimals: spotQuoteAmount,
                    oppositeAmountXSpotDecimals: spotBaseAmount
                })
            )
        );

        // Maker won't withdraw its USDC for swap, because it only makes quotations, not directly swaps
        uint256 vaultCollateralBalanceAfter = collateralToken.balanceOf(address(vault));
        assertEq(vaultCollateralBalanceAfter, vaultCollateralBalanceBefore);

        // Maker should acquired ETH.
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(address(maker));
        assertEq(makerBaseBalanceAfter, makerBaseBalanceBefore);
    }

    function testFuzz_fillOrder_B2Q_exactOutput_Normal(uint256 quoteAmount) public {
        // Fuzz test and assume:
        // - There will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        // - Minimum amount of 1e12 or otherwise spotQuoteAmount will be zero
        vm.assume(quoteAmount > 1e12 && quoteAmount < 1e36);

        // perpBaseAmount: 18-decimal
        // perpQuoteAmount: 18-decimal
        // spotBaseAmount: 9-decimal
        // spotQuoteAmount: 6-decimal

        // Price = $100
        uint256 spotBaseAmount = quoteAmount / 100 / 10 ** (18 - 9); // Convert from 18-decimal to 9-decimal
        uint256 spotQuoteAmount = quoteAmount / 10 ** (18 - 6); // Convert from 18-decimal to 6-decimal
        uint256 expectedBaseAmount = spotBaseAmount * 10 ** (18 - 9); // Convert from 9-decimal to 18-decimal

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        // Fake uniswap router behavior.
        uniswapV3Router.setAmountIn(
            ISwapRouter.ExactOutputParams({
                path: uniswapV3Q2BPath,
                recipient: address(maker),
                deadline: block.timestamp,
                amountOut: spotQuoteAmount,
                amountInMaximum: makerBaseBalanceBefore
            }),
            spotBaseAmount
        );

        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.SHMOrderFilled(
            marketId,
            uniswapV3Q2BPath, // path
            true, // isBaseToQuote
            false, // isExactInput
            quoteAmount, // targetAmount
            expectedBaseAmount, // oppositeAmount,
            0 // spread
        );
        vm.prank(address(clearingHouse));
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            true, // isBaseToQuote
            false, // isExactInput
            quoteAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedBaseAmount, 18);
        assertEq(
            callbackData,
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: true,
                    isExactInput: false,
                    amountXSpotDecimals: spotQuoteAmount,
                    oppositeAmountXSpotDecimals: spotBaseAmount
                })
            )
        );

        // Maker should swap out its ETH.
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(address(maker));
        assertEq(makerBaseBalanceAfter, makerBaseBalanceBefore - spotBaseAmount);

        // Maker should deposit the USDC acquired to vault.
        uint256 vaultCollateralBalanceAfter = collateralToken.balanceOf(address(vault));
        assertEq(vaultCollateralBalanceAfter, vaultCollateralBalanceBefore + spotQuoteAmount);
    }

    function testFuzz_fillOrder_Q2B_exactOutput_Normal(uint256 baseAmount) public {
        // Fuzz test and assume:
        // - There will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        // - Minimum amount of 1e10 or otherwise spotQuoteAmount will be zero
        vm.assume(baseAmount > 1e10 && baseAmount < 1e36);

        // perpBaseAmount: 18-decimal
        // perpQuoteAmount: 18-decimal
        // spotBaseAmount: 9-decimal
        // spotQuoteAmount: 6-decimal

        // Price = $100
        uint256 spotBaseAmount = baseAmount / 10 ** (18 - 9); // Convert from 18-decimal to 9-decimal
        uint256 spotQuoteAmount = (baseAmount * 100) / 10 ** (18 - 6); // Convert from 18-decimal to 6-decimal
        uint256 expectedQuoteAmount = spotQuoteAmount * 10 ** (18 - 6); // Convert from 6-decimal to 18-decimal

        // Fake uniswap quoter behavior.
        uniswapV3Quoter.setAmountIn(uniswapV3B2QPath, spotBaseAmount, spotQuoteAmount);

        uint256 makerBaseBalanceBefore = baseToken.balanceOf(address(maker));
        uint256 vaultCollateralBalanceBefore = collateralToken.balanceOf(address(vault));

        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.SHMOrderFilled(
            marketId,
            uniswapV3B2QPath, // path
            false, // isBaseToQuote
            false, // isExactInput
            baseAmount, // targetAmount
            expectedQuoteAmount, // oppositeAmount,
            0 // spread
        );
        vm.prank(address(clearingHouse));
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            false, // isBaseToQuote
            false, // isExactInput
            baseAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedQuoteAmount, 18);
        assertEq(
            callbackData,
            abi.encode(
                SpotHedgeBaseMaker.FillOrderCallbackData({
                    isBaseToQuote: false,
                    isExactInput: false,
                    amountXSpotDecimals: spotBaseAmount,
                    oppositeAmountXSpotDecimals: spotQuoteAmount
                })
            )
        );

        // Maker won't withdraw its USDC for swap, because it only makes quotations, not directly swaps
        uint256 vaultCollateralBalanceAfter = collateralToken.balanceOf(address(vault));
        assertEq(vaultCollateralBalanceAfter, vaultCollateralBalanceBefore);

        // Maker should acquired ETH.
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(address(maker));
        assertEq(makerBaseBalanceAfter, makerBaseBalanceBefore);
    }
}
