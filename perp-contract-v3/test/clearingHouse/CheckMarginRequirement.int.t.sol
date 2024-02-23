// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { TestMaker } from "../helper/TestMaker.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { ClearingHouseIntSetup } from "./ClearingHouseIntSetup.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";

contract CheckMarginRequirementInt is ClearingHouseIntSetup {
    TestMaker public maker;
    address public taker = makeAddr("taker");
    address public taker2 = makeAddr("taker2");

    function setUp() public override {
        super.setUp();

        maker = _newMarketWithTestMaker(marketId);
        maker.setBaseToQuotePrice(100e18);
        _mockPythPrice(100, 0);

        _deposit(marketId, address(maker), 10000e6);
        _deposit(marketId, taker, 1000e6);
        _deposit(marketId, taker2, 20000e6);
    }

    function test_RevertIf_TakerIncreasePositionAndBelowIMRatio() public {
        // taker long 101 ether, > 10x leverage and lower than initial margin requirement
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 101 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_TakerReversePositionAndBelowIMRatio() public {
        // taker long 100 ether, 10x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker short -201  ether, reverse long position to -101 ether and below IM ratio (10%)
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 201 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_TakerReducePositionAndBelowMMRatio() public {
        // taker long 100 ether, 10x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker reduce position by 10% and no longer has enough free collateral due to realized loss
        // new market price = 95 (-5% drop)
        // realizedPnl = 100 * 0.1 * (95 - 100) = -50
        // unrealizedPnl = 100 * 0.9 * (95 - 100) = -450
        // marginState = 1000 + (-50) = 950
        // accountValue = 950 + (-450) = 500
        // openNotional = 100 * 100 * 0.9 = 9000
        // freeCollateralForReduce = min(margin, accountValue) - positionMarginRequirement(mmRatio)
        //                         = min(950, 500) - 9000 * 0.0625
        //                         = -62.5 < 0
        maker.setBaseToQuotePrice(95e18);
        _mockPythPrice(95, 0);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 10 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_TakerClosePositionAndHasBadDebt() public {
        // taker long 100 ether, 10x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker close position and no longer has enough free collateral due to realized loss
        // new market price = 89 (-11% drop)
        // realizedPnl = 100 * (89 - 100) = -1,100
        // marginState = accountValue = 1000 + (-1,100) = -100
        // freeCollateralForReduce = min(margin, accountValue) - positionMarginRequirement(mmRatio)
        //                         = min(-100, -100) - 0
        //                         = -100 < 0
        maker.setBaseToQuotePrice(89e18);
        _mockPythPrice(89, 0);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));
        vm.prank(taker);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_TakerClosePositionIndirectlyAndHasBadDebt() public {
        // taker long 100 ether, 10x leverage
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker close position indirectly by shorting 100% and no longer has enough free collateral due to realized loss
        // new market price = 89 (-11% drop)
        // realizedPnl = 100 * (89 - 100) = -1,100
        // marginState = accountValue = 1000 + (-1,100) = -100
        // freeCollateralForReduce = min(margin, accountValue) - positionMarginRequirement(mmRatio)
        //                         = min(-100, -100) - 0
        //                         = -100 < 0
        maker.setBaseToQuotePrice(89e18);
        _mockPythPrice(89, 0);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, taker));
        vm.prank(taker);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 100 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_MakerIncreasePositionAndBelowIMRatio() public {
        // taker2 long 1001 ether, maker > 10x leverage and lower than initial margin requirement
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, maker));
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1001 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_MakerReversePositionAndBelowIMRatio() public {
        // taker2 long ether, maker short with 10x leverage
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1000 ether,
                oppositeAmountBound: type(uint).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker2 reverse long, maker reverse short and below IM ratio
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, maker));
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 2001 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_MakerReducePositionAndBelowMMRatio() public {
        // taker2 short ether, maker long with 10x leverage
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1000 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker reduce position by 10% as well as the maker, and the maker no longer has enough free collateral due to realized loss
        // new market price = 95 (-5% drop)
        // realizedPnl = 1000 * 0.1 * (95 - 100) = -500
        // unrealizedPnl = 1000 * 0.9 * (95 - 100) = -4500
        // marginState = 10000 + (-500) = 9500
        // accountValue = 9500 + (-4500) = 5000
        // openNotional = 1000 * 100 * 0.9 = 90000
        // freeCollateralForReduce = min(margin, accountValue) - positionMarginRequirement(mmRatio)
        //                         = min(9500, 5000) - 90000 * 0.0625
        //                         = -625 < 0
        maker.setBaseToQuotePrice(95e18);
        _mockPythPrice(95, 0);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, maker));
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 100 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_MakerClosePositionAndHasBadDebt() public {
        // taker2 short ether, maker long with 10x leverage
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1000 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker close position as well as the maker, and the maker no longer has enough free collateral due to realized loss
        // new market price = 89 (-11% drop)
        // realizedPnl = 1000 * (89 - 100) = -11000
        // marginState = accountValue = 10000 + (-11000) = -1000
        // freeCollateralForReduce = min(margin, accountValue) - positionMarginRequirement(mmRatio)
        //                         = min(-1000, -1000) - 0
        //                         = -1000 < 0
        maker.setBaseToQuotePrice(89e18);
        _mockPythPrice(89, 0);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, maker));
        vm.prank(taker2);
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function test_RevertIf_MakerClosePositionIndirectlyAndHasBadDebt() public {
        // taker2 short ether, maker long with 10x leverage
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1000 ether,
                oppositeAmountBound: 0 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // taker close position indirectly by longing 100%, effectively closing the maker, and the maker no longer has enough free collateral due to realized loss
        // new market price = 89 (-11% drop)
        // realizedPnl = 1000 * (89 - 100) = -11000
        // marginState = accountValue = 10000 + (-11000) = -1000
        // freeCollateralForReduce = min(margin, accountValue) - positionMarginRequirement(mmRatio)
        //                         = min(-1000, -1000) - 0
        //                         = -1000 < 0
        maker.setBaseToQuotePrice(89e18);
        _mockPythPrice(89, 0);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotEnoughFreeCollateral.selector, marketId, maker));
        vm.prank(taker2);
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 1000 ether,
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }
}
