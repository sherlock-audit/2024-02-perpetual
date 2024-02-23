// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { SpotHedgeBaseMakerIntSetup } from "./SpotHedgeBaseMakerIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { LibError } from "../../src/common/LibError.sol";

contract SpotHedgeBaseMakerWithdrawInt is SpotHedgeBaseMakerIntSetup {
    address public lp1 = makeAddr("LP1");
    address public lp2 = makeAddr("LP2");
    address public taker = makeAddr("Taker");
    uint256 shares;

    function setUp() public virtual override {
        SpotHedgeBaseMakerIntSetup.setUp();

        _mockPythPrice(100, 0);

        // LP1 deposit 1 WETH to Maker
        uint256 amount = 1e9;
        deal(address(baseToken), lp1, amount, true);
        vm.startPrank(lp1);
        baseToken.approve(address(maker), amount);
        shares = maker.deposit(amount);
        vm.stopPrank();

        // taker deposit 1000 USDC to ClearingHouse
        _deposit(marketId, taker, 1000e6);
    }

    function test_withdraw_Single_LP_no_positions() public {
        int256 marginRatioBefore = _getMarginProfile(marketId, address(maker), 100e18).marginRatio;

        vm.startPrank(lp1);
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.Withdrawn(lp1, shares, 1e9, 0);
        maker.withdraw(shares);

        int256 marginRatioAfter = _getMarginProfile(marketId, address(maker), 100e18).marginRatio;

        assertEq(baseToken.balanceOf(address(lp1)), 1e9);
        assertEq(baseToken.balanceOf(address(maker)), 0);
        assertEq(maker.balanceOf(address(lp1)), 0);
        assertEq(maker.baseTokenLiability(), 0);
        assertEq(marginRatioAfter, marginRatioBefore);
        vm.stopPrank();
    }

    function test_withdraw_Multiple_LP_with_positions() public {
        // LP2 deposit 1 WETH to Maker
        uint256 lp2DepositAmount = 1e9;
        deal(address(baseToken), lp2, lp2DepositAmount, true);
        vm.startPrank(lp2);
        baseToken.approve(address(maker), lp2DepositAmount);
        uint256 lp2Shares = maker.deposit(lp2DepositAmount);
        vm.stopPrank();

        assertEq(lp2Shares, lp2DepositAmount);

        // Fake uniswap router behavior for fillOrder.
        uniswapV3Router.setAmountOut(
            ISwapRouter.ExactInputParams({
                path: uniswapV3B2QPath,
                recipient: address(maker),
                deadline: block.timestamp,
                amountIn: 0.3e9, // 0.3 WETH
                amountOutMinimum: 0
            }),
            30e6 // 30 USDC
        );

        // taker short 0.3 ether with avg price = 100
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 0.3 ether,
                oppositeAmountBound: 30 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        //
        // LP1 withdraw all should succeed
        //
        // maker account value (in base) = 30 / 100 = 0.3
        // maker spot balance = 2 - 0.3 = 1.7
        // vault value (in base) = 0.3 + 1.7 = 2
        // withdraw value (in base) = 1 < 1.7
        vm.prank(lp1);
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.Withdrawn(lp1, shares, 1e9, 0);
        maker.withdraw(shares);

        // maker account value (in base) = 30 / 100 = 0.3
        // maker spot balance = 1.7 - 1 = 0.7
        assertEq(baseToken.balanceOf(address(lp1)), 1e9);
        assertEq(baseToken.balanceOf(address(maker)), 0.7e9);
        assertEq(maker.balanceOf(address(lp1)), 0);
        assertEq(maker.baseTokenLiability(), 1e9);
        {
            (, uint256 shortUtilRatio) = maker.getUtilRatio();
            assertEq(shortUtilRatio, 0.3e18);
        }

        //
        // LP2 withdraw all should fail.
        //
        // vault value (in base) = 0.3 + 0.7 = 1
        // withdraw value (in base) = 1 > 0.7, revert
        vm.prank(lp2);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughSpotBaseTokens.selector, 1e9, 0.7e9));
        maker.withdraw(shares);

        //
        // Withdraw exactly all available should work.
        //
        vm.prank(lp2);
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.Withdrawn(lp2, (lp2Shares * 7) / 10, 0.7e9, 0);
        maker.withdraw((lp2Shares * 7) / 10);

        // maker spot balance = 0.7 - 0.7 = 0
        assertEq(baseToken.balanceOf(address(lp2)), 0.7e9);
        assertEq(baseToken.balanceOf(address(maker)), 0);
        assertEq(maker.balanceOf(address(lp2)), 0.3e9);
        assertEq(maker.baseTokenLiability(), 0.3e9);
        {
            (, uint256 shortUtilRatio) = maker.getUtilRatio();
            assertEq(shortUtilRatio, 1e18);
        }
    }

    function test_withdraw_Multiple_LP_with_profits() public {
        // LP2 deposit 1 WETH to Maker
        uint256 lp2DepositAmount = 1e9;
        deal(address(baseToken), lp2, lp2DepositAmount, true);
        vm.startPrank(lp2);
        baseToken.approve(address(maker), lp2DepositAmount);
        uint256 lp2Shares = maker.deposit(lp2DepositAmount);
        vm.stopPrank();

        assertEq(lp2Shares, lp2DepositAmount);

        //
        // Simulate maker profits:
        //

        // We take a shortcut here and simulate maker's fee profits by just depositing USDC for it.
        uint256 profit = 10e6; // 10 USDC
        _deposit(marketId, address(maker), profit);

        // After the profits:
        // maker account value (in base) = 10 / 100 = 0.1
        // maker spot balance = 2
        // vault value (in base) = 0.1 + 2 = 2.1

        //
        // LP1 withdraw all should succeed
        //
        // withdraw value (in base) = 2.1 * 1 / 2 = 1.05 < 2, success
        vm.prank(lp1);
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.Withdrawn(lp1, shares, 1.05e9, 0);
        maker.withdraw(shares);
        // After withdrawal:
        // maker account value (in base) = 10 / 100 = 0.1
        // maker spot balance = 2 - 1.05 = 0.95
        // vault value (in base) = 0.1 + 0.95 = 1.05
        // maker liability = 2 - 2 * 1 / 2 = 1
        // maker util ratio = 0.95 / 1 = 0.95

        assertEq(baseToken.balanceOf(address(lp1)), 1.05e9);
        assertEq(baseToken.balanceOf(address(maker)), 0.95e9);
        assertEq(maker.balanceOf(address(lp1)), 0);
        assertEq(maker.baseTokenLiability(), 1e9);
        {
            (, uint256 shortUtilRatio) = maker.getUtilRatio();
            assertEq(shortUtilRatio, 0.05e18);
        }

        //
        // LP2 withdraw all should succeed with mix assets.
        //
        // withdraw value (in base) = 1.05 * 1 / 1 = 1.05 < 0.95, spot asset not enough
        // actual withdraw value (in base) = min(1.05, 0.95) = 0.95
        // actual withdraw value (in quote) = (1.05 - 0.95) * 100 = 10
        vm.prank(lp2);
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.Withdrawn(lp2, lp2Shares, 0.95e9, 10e6);
        maker.withdraw(lp2Shares);
        // After withdrawal:
        // maker account value (in base) = (10 - 10) / 100 = 0
        // maker spot balance = 0.95 - 0.95 = 0
        // vault value (in base) = 0 + 0 = 0
        // maker liability = 1 - 1 * 1 / 1 = 0
        // maker util ratio = 0

        assertEq(baseToken.balanceOf(address(lp2)), 0.95e9);
        assertEq(collateralToken.balanceOf(address(lp2)), 10e6);
        assertEq(baseToken.balanceOf(address(maker)), 0);
        assertEq(maker.balanceOf(address(lp2)), 0);
        assertEq(maker.baseTokenLiability(), 0);
        {
            (, uint256 shortUtilRatio) = maker.getUtilRatio();
            assertEq(shortUtilRatio, 0);
        }
    }

    function test_withdraw_RevertIf_amount_is_zero() public {
        vm.prank(lp1);
        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAmount.selector));
        maker.withdraw(0);
    }
}
