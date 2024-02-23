// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { OracleMakerIntSetup } from "./OracleMakerIntSetup.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { LibError } from "../../src/common/LibError.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract OracleMakerWithdrawInt is OracleMakerIntSetup {
    address public taker1 = makeAddr("taker1");
    address public taker2 = makeAddr("taker2");
    uint256 shares;

    function setUp() public virtual override {
        super.setUp();

        maker.setValidSender(taker1, true);
        maker.setValidSender(taker2, true);

        // taker1 deposit 1000 as LP
        uint256 amount = 1000e6;
        deal(address(collateralToken), taker1, amount, true);
        vm.startPrank(taker1);
        collateralToken.approve(address(maker), amount);
        shares = maker.deposit(amount);
        vm.stopPrank();

        // taker2 deposit 1000
        _deposit(marketId, taker2, 1000e6);

        _mockPythPrice(100, 0);
    }

    function test_withdraw_Normal() public {
        vm.startPrank(taker1);
        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.Withdrawn(taker1, shares, 1000e6);
        maker.withdraw(shares);

        assertEq(collateralToken.balanceOf(address(taker1)), 1000e6);
        assertEq(collateralToken.balanceOf(address(maker)), 0);
        vm.stopPrank();
    }

    function test_withdraw_Normal_above_minMarginRatio() public {
        // taker short 5 ether with avg price = 100
        vm.prank(taker2);
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

        _mockPythPrice(90, 0);
        // maker account value = 1000 - 5 * 10 = 950
        // maker share price = 950 / 1000 = 0.95
        // maker free collateral (checkMargin) = 950 - 500 * 100% = 450

        vm.prank(taker1);
        // withdrawn amount = 950 / 4 = 237.5
        uint256 withdrawnAmount = maker.withdraw(shares / 4);
        assertEq(withdrawnAmount, 237.5e6);
        assertEq(collateralToken.balanceOf(address(taker1)), 237.5e6);
    }

    function test_withdraw_ReverIf_below_minMarginRatio() public {
        // taker short 5 ether with avg price = 100
        vm.prank(taker2);
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

        _mockPythPrice(90, 0);
        // maker account value = 1000 - 5 * 10 = 950
        // maker share price = 950 / 1000 = 0.95
        // maker free collateral (checkMargin) = 950 - 450 * 100% = 500

        vm.prank(taker1);
        // withdrawn amount = 950 * 2/3 = 633.33
        // margin ratio after withdrawn = (950 - 633.33) / 500 = 0.63333
        vm.expectRevert(abi.encodeWithSelector(LibError.MinMarginRatioExceeded.selector, 0.633333336 ether, 1e18));
        maker.withdraw((shares * 2) / 3);
    }

    function test_withdraw_ReverIf_NotEnoughFreeCollateral() public {
        // taker long 10 ether with avg price = 100
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        _mockPythPrice(10, 0);
        // maker account value = 1000 + 10 * 90 = 1900
        // maker share price = 1900 / 1000 = 1.9
        // maker free collateral (checkMargin) = 1900 - 100 * 100% = 1800

        vm.prank(taker1);
        // withdrawn amount = 1800 * 2/3 = 1200
        // free collateral = min(1000, 1900) - 1000 * 10% = 900
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, address(maker)));
        maker.withdraw((shares * 2) / 3);
    }

    function test_withdraw_ReverIf_NegativeAccountValue() public {
        // taker long 10 ether with avg price = 100
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 10 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        _mockPythPrice(300, 0);
        // maker account value = 1000 - 10 * 200 = -1000
        // maker share price = -1000 / 1000 = -1

        vm.prank(taker1);
        // -1000e18 * 1e18 / 1000e6 = -1e30
        vm.expectRevert(abi.encodeWithSelector(LibError.NegativeOrZeroVaultValueInQuote.selector, -1000e18));
        maker.withdraw((shares * 2) / 3);
    }

    function test_withdraw_RevertIf_amount_is_zero() public {
        vm.prank(taker1);
        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAmount.selector));
        maker.withdraw(0);
    }
}
