// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { SpotHedgeBaseMakerIntSetup } from "./SpotHedgeBaseMakerIntSetup.sol";

contract SpotHedgeBaseMakerDepositInt is SpotHedgeBaseMakerIntSetup {
    address public lp = makeAddr("LiquidityProvider");
    address public lp2 = makeAddr("LiquidityProvider2");
    address public taker = makeAddr("Taker");

    function setUp() public virtual override {
        SpotHedgeBaseMakerIntSetup.setUp();

        _mockPythPrice(100, 0);
    }

    function test_deposit_Normal() public {
        uint256 amount = 1e9; // 1 WETH

        // 1. first deposit
        {
            deal(address(baseToken), lp, amount, true);
            vm.startPrank(lp);
            baseToken.approve(address(maker), amount);

            uint256 shares = maker.deposit(amount);

            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp), shares);
            assertEq(baseToken.balanceOf(address(lp)), 0);
            assertEq(baseToken.balanceOf(address(maker)), amount);
            assertEq(maker.baseTokenLiability(), amount);
            vm.stopPrank();
        }

        // 2. second deposit
        {
            deal(address(baseToken), lp2, amount, true);
            vm.startPrank(lp2);
            baseToken.approve(address(maker), amount);

            uint256 baseTokenBalanceBefore = baseToken.balanceOf(address(maker));

            uint256 shares = maker.deposit(amount);

            uint256 baseTokenBalanceAfter = baseToken.balanceOf(address(maker));

            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp2), shares);
            assertEq(baseToken.balanceOf(address(lp)), 0);
            assertEq(baseTokenBalanceAfter - baseTokenBalanceBefore, amount);
            assertEq(maker.baseTokenLiability(), amount * 2);
            vm.stopPrank();
        }
    }

    function test_deposit_Normal_has_position() public {
        uint256 amount = 1e9; // 1 WETH

        // 1. first deposit
        {
            deal(address(baseToken), lp, amount, true);
            vm.startPrank(lp);
            baseToken.approve(address(maker), amount);

            uint256 shares = maker.deposit(amount);

            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp), shares);
            assertEq(baseToken.balanceOf(address(lp)), 0);
            assertEq(baseToken.balanceOf(address(maker)), amount);
            assertEq(maker.baseTokenLiability(), amount);
            vm.stopPrank();
        }

        // 2. trade
        {
            // Fake uniswap router behavior.
            uniswapV3Router.setAmountOut(
                ISwapRouter.ExactInputParams({
                    path: uniswapV3B2QPath,
                    recipient: address(maker),
                    deadline: block.timestamp,
                    amountIn: 0.5e9, // 0.5 WETH
                    amountOutMinimum: 0
                }),
                50e6 // 50 USDC
            );

            // taker2 deposit 1000
            _deposit(marketId, taker, 1000e6);
            vm.prank(taker);
            clearingHouse.openPosition(
                IClearingHouse.OpenPositionParams({
                    marketId: marketId,
                    maker: address(maker),
                    isBaseToQuote: true,
                    isExactInput: true,
                    amount: 0.5 ether,
                    oppositeAmountBound: 50 ether,
                    deadline: block.timestamp,
                    makerData: ""
                })
            );
        }

        // 3. second deposit
        {
            _mockPythPrice(90, 0);

            deal(address(baseToken), lp2, amount, true);
            vm.startPrank(lp2);
            baseToken.approve(address(maker), amount);

            uint256 baseTokenBalanceBefore = baseToken.balanceOf(address(maker));

            uint256 shares = maker.deposit(amount);

            uint256 baseTokenBalanceAfter = baseToken.balanceOf(address(maker));

            // maker account value (in base) = (50 - 0.5 * 10) / 90 = 0.5
            // maker spot balance = 1 - 0.5 = 0.5
            // maker vault value (in base) = 0.5 + 0.5 = 1
            // share price = 1 / 1 = 1
            // new share = 1 / 1 = 1
            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp2), shares);
            assertEq(baseToken.balanceOf(address(lp)), 0);
            assertEq(baseTokenBalanceAfter - baseTokenBalanceBefore, amount);
            assertEq(maker.baseTokenLiability(), amount * 2);
            vm.stopPrank();
        }
    }
}
