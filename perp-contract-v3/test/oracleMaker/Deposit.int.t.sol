// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./OracleMakerIntSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract OracleMakerDepositInt is OracleMakerIntSetup {
    address public lp = makeAddr("LiquidityProvider");
    address public lp2 = makeAddr("LiquidityProvider2");
    address public taker = makeAddr("Taker");

    function setUp() public virtual override {
        super.setUp();
        maker.setValidSender(taker, true);
        _mockPythPrice(100, 0);
    }

    function test_deposit_Normal() public {
        uint256 amount = 1000e6; // 1000

        // 1. first deposit
        {
            deal(address(collateralToken), lp, amount, true);
            vm.startPrank(lp);
            collateralToken.approve(address(maker), amount);

            uint256 collateralTokenBalanceBefore = collateralToken.balanceOf(address(vault));

            uint256 shares = maker.deposit(amount);

            uint256 collateralTokenBalanceAfter = collateralToken.balanceOf(address(vault));

            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp), shares);
            assertEq(collateralToken.balanceOf(address(maker)), 0);
            assertEq(collateralTokenBalanceAfter - collateralTokenBalanceBefore, amount);
            vm.stopPrank();
        }

        // 2. second deposit
        {
            deal(address(collateralToken), lp2, amount, true);
            vm.startPrank(lp2);
            collateralToken.approve(address(maker), amount);

            uint256 collateralTokenBalanceBefore = collateralToken.balanceOf(address(vault));

            uint256 shares = maker.deposit(amount);

            uint256 collateralTokenBalanceAfter = collateralToken.balanceOf(address(vault));

            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp2), shares);
            assertEq(collateralToken.balanceOf(address(maker)), 0);
            assertEq(collateralTokenBalanceAfter - collateralTokenBalanceBefore, amount);
            vm.stopPrank();
        }
    }

    function test_deposit_NormalIf_has_position() public {
        uint256 amount = 1000 * (10 ** collateralToken.decimals());

        // 1. first deposit
        {
            deal(address(collateralToken), lp, amount, true);
            vm.startPrank(lp);
            collateralToken.approve(address(maker), amount);

            uint256 collateralTokenBalanceBefore = collateralToken.balanceOf(address(vault));

            uint256 shares = maker.deposit(amount);

            uint256 collateralTokenBalanceAfter = collateralToken.balanceOf(address(vault));

            assertEq(shares, amount);
            assertEq(maker.balanceOf(lp), shares);
            assertEq(collateralToken.balanceOf(address(maker)), 0);
            assertEq(collateralTokenBalanceAfter - collateralTokenBalanceBefore, amount);
            vm.stopPrank();
        }

        // 2. trade
        {
            // taker2 deposit 1000
            _deposit(marketId, taker, 1000e6);
            vm.prank(taker);
            clearingHouse.openPosition(
                IClearingHouse.OpenPositionParams({
                    marketId: marketId,
                    maker: address(maker),
                    isBaseToQuote: true,
                    isExactInput: true,
                    amount: 5 ether,
                    oppositeAmountBound: 500 ether,
                    deadline: block.timestamp,
                    makerData: ""
                })
            );
        }

        // 3. second deposit
        {
            _mockPythPrice(90, 0);

            deal(address(collateralToken), lp2, amount, true);
            vm.startPrank(lp2);
            collateralToken.approve(address(maker), amount);

            uint256 collateralTokenBalanceBefore = collateralToken.balanceOf(address(vault));

            uint256 shares = maker.deposit(amount);

            uint256 collateralTokenBalanceAfter = collateralToken.balanceOf(address(vault));

            // maker account value = 1000 - 5 * 10 = 950
            // maker share price = 950 / 1000 = 0.95
            // share = 1000 / 0.95 = 1052.631578
            assertEq(shares, 1052631578);
            assertEq(maker.balanceOf(lp2), shares);
            assertEq(collateralToken.balanceOf(address(maker)), 0);
            assertEq(collateralTokenBalanceAfter - collateralTokenBalanceBefore, amount);
            vm.stopPrank();
        }
    }

    function test_deposit_RevertIf_amount_is_zero() public {
        vm.startPrank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAmount.selector));
        maker.deposit(0);
        vm.stopPrank();
    }

    function test_deposit_RevertIf_collateralToken_is_deflationaryToken() public {
        _setCollateralTokenAsDeflationaryToken();

        uint256 deflationaryTokenTransferFee = deflationaryCollateralToken.fee();
        uint256 amount = 1000;

        deal(address(deflationaryCollateralToken), lp, amount, true);

        vm.startPrank(lp);
        deflationaryCollateralToken.approve(address(maker), amount);

        vm.expectRevert(
            abi.encodeWithSelector(LibError.WrongTransferAmount.selector, amount - deflationaryTokenTransferFee, amount)
        );
        maker.deposit(amount);
        vm.stopPrank();
    }
}
