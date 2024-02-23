// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { TestMaker } from "../helper/TestMaker.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import "./ClearingHouseIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract WithdrawInt is ClearingHouseIntSetup, IERC20Errors {
    address taker = makeAddr("taker");
    TestMaker maker1;

    function setUp() public override {
        super.setUp();
        maker1 = _newMarketWithTestMaker(marketId);
    }

    // TODO delete this
    function _createMaker(uint256 fund) internal returns (TestMaker) {
        TestMaker maker = new TestMaker(vault);
        config.registerMaker(marketId, address(maker));
        _deposit(marketId, address(maker), fund * 1e6);
        return maker;
    }

    function test_Success() public {
        // taker deposit 100
        _deposit(marketId, taker, 100e6);

        _mockPythPrice(150, 0);

        vm.startPrank(taker);

        vault.transferMarginToFund(marketId, 100e6);
        vault.withdraw(100e6);

        _assertEq(
            _getMarginProfile(marketId, taker, 0),
            LegacyMarginProfile({
                positionSize: 0 ether,
                openNotional: 0 ether,
                accountValue: 0 ether,
                unrealizedPnl: 0 ether,
                freeCollateral: 0 ether,
                freeCollateralForOpen: 0 ether, // min(0, 0) - 0 = 0
                freeCollateralForReduce: 0 ether, // min(0, 0) - 0 = 0
                marginRatio: type(int256).max
            })
        );

        assertEq(collateralToken.balanceOf(taker), 100e6);
        assertEq(collateralToken.balanceOf(address(vault)), 0);
    }

    function test_SettlePnl() public {
        TestMaker maker01 = _createMaker(10000); // 10000 USDC
        TestMaker maker02 = _createMaker(10000); // 10000 USDC

        // taker deposit 100
        _deposit(marketId, taker, 100e6);

        _mockPythPrice(100, 0);
        vm.startPrank(taker);

        // Alice take 1 long against maker01
        maker01.setBaseToQuotePrice(100 ether);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker01),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 100 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 100 ether, positionSize: 1 ether, openNotional: -100 ether, unsettledPnl: 0 })
        );

        // Alice close 1 long against maker02 and realizes profit.
        // Note it was maker02 instead of maker01 so that maker01 does not realize PnL and interfere PnL Pool.

        maker02.setBaseToQuotePrice(110 ether);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker02),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1 ether,
                oppositeAmountBound: 110 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        // Alice will have unsettled PnL because PnL Pool is empty.
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 110 ether, positionSize: 0, openNotional: 0, unsettledPnl: 10 ether })
        );

        // Alice withdraw, should emit PnLSettled event even though PnL Pool is empty.
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PnlSettled(
            marketId,
            address(taker),
            0, // realizedPnl
            0, // settledPnl
            100 ether, // margin
            10 ether, // unsettledPnl
            0 // pnlPoolBalance
        );
        vault.transferMarginToFund(marketId, 1e6);
        vault.withdraw(1e6);

        vm.stopPrank();
    }

    function test_MulticallDepositWithdraw() public {
        deal(address(collateralToken), taker, 100e6, true);

        vm.startPrank(taker);

        address[] memory targets = new address[](2);
        targets[0] = address(vault);
        targets[1] = address(vault);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(Vault.deposit.selector, taker, 100e6);
        data[1] = abi.encodeWithSelector(Vault.withdraw.selector, 80e6);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(vault), 0, 100e6));
        multicallerWithSender.aggregateWithSender(targets, data, values);

        collateralToken.approve(address(vault), type(uint256).max);
        multicallerWithSender.aggregateWithSender(targets, data, values);

        assertEq(collateralToken.balanceOf(taker), 80e6);
        assertEq(collateralToken.balanceOf(address(vault)), 20e6);
        assertEq(vault.getFund(taker), 20e6);
    }

    function test_RevertIf_NotEnoughFreeCollateral() public {
        // taker deposit 100
        _deposit(marketId, address(maker1), 10000e6);
        maker1.setBaseToQuotePrice(150e18);
        _mockPythPrice(150, 0);
        _deposit(marketId, taker, 100e6);

        // taker long 1 eth@1000
        _mockPythPrice(1000, 0);
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker1),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1 ether,
                oppositeAmountBound: 1000 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
        _mockPythPrice(150, 0);

        // margin = 100, size = 1, openNotional = -1000
        // free collateral = 100 - (1000 - 150) - 1000 * 10% = -850
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));

        vm.prank(taker);
        vault.transferMarginToFund(marketId, 100e6);
    }
}
