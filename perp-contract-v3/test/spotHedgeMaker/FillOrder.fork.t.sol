// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../spotHedgeMaker/SpotHedgeBaseMakerForkSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";

contract SpotHedgeBaseMakerFillOrderFork is SpotHedgeBaseMakerForkSetup {
    address public taker = makeAddr("Taker");

    function setUp() public override {
        super.setUp();

        _deposit(marketId, taker, 1000e6);
    }

    // TODO: Should test multi-hop paths.

    function test_fillOrder_exactInput_and_exactOutput() public {
        vm.startPrank(taker);

        address[] memory targets = new address[](2);
        targets[0] = address(pythOracleAdapter);
        targets[1] = address(clearingHouse);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IPythOracleAdapter.updatePrice.selector, priceFeedId, priceUpdateData);
        data[1] = abi.encodeWithSelector(
            IClearingHouse.openPosition.selector,
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 1 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        // update price before opening position
        // taker short 1 ether
        multicallerWithSender.aggregateWithSender(targets, data, values);

        _assertEq(
            _getMarginProfile(marketId, taker, 0), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: -1 ether,
                openNotional: 1974.316068 ether, // Due to slippage (spot price = 2000)
                accountValue: 2974.316068 ether,
                unrealizedPnl: 1974.316068 ether,
                freeCollateral: 802.5683932 ether,
                freeCollateralForOpen: 802.5683932 ether, // min(1000, 2974.316068) - 1974.316068 * 0.1 = 802.5683932
                freeCollateralForReduce: 876.60524575 ether, // min(1000, 2974.316068) - 1974.316068 * 0.0625 = 876.60524575
                // 2974.316068/1974.316068=1.506505
                marginRatio: 1.506504513744351494 ether
            })
        );

        _assertEq(
            _getMarginProfile(marketId, address(maker), 0), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 1 ether,
                openNotional: -1974.316068 ether,
                accountValue: 0 ether,
                unrealizedPnl: -1974.316068 ether,
                freeCollateral: 0 ether,
                freeCollateralForOpen: -197.4316068 ether, // min(1974.316068, 0) - 1974.316068 * 0.1 = -197.4316068
                freeCollateralForReduce: -123.39475425 ether, // min(1974.316068, 0) - 1974.316068 * 0.0625 = -123.39475425
                marginRatio: 0
            })
        );

        // Maker should swap all its ETH for USDC (and deposit it)
        assertEq(baseToken.balanceOf(address(maker)), 0);
        assertEq(collateralToken.balanceOf(address(maker)), 0);
        assertEq(collateralToken.balanceOf(address(vault)), 2974.316068e6);

        // taker close
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                marketId: marketId,
                maker: address(maker),
                oppositeAmountBound: type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        // Taker realized loss = 1974.316068 - 1986.275075 = -11.959007
        // Taker margin after close = 1000 - 11.959007 = 988.040993
        // It makes sense because taker's estimate cost is determined by Uniswap fee ratio (both directions) ~= 2000 * 0.003 * 2 = 12 (which is close to 11.959007)

        _assertEq(
            _getMarginProfile(marketId, taker, 0), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 0 ether,
                openNotional: 0 ether,
                accountValue: 988.040993 ether,
                unrealizedPnl: 0 ether,
                freeCollateral: 988.040993 ether,
                freeCollateralForOpen: 988.040993 ether, // min(988.040993, 988.040993) - 0 = 988.040993
                freeCollateralForReduce: 988.040993 ether, // min(988.040993, 988.040993) - 0 = 988.040993
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );

        _assertEq(
            _getMarginProfile(marketId, address(maker), 0), // Assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 0 ether,
                openNotional: 0 ether,
                accountValue: 0 ether,
                unrealizedPnl: 0 ether,
                freeCollateral: 0 ether,
                freeCollateralForOpen: 0 ether, // min(0, 0) - 0 = 0
                freeCollateralForReduce: 0 ether, // min(0, 0) - 0 = 0
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );

        // Maker should withdraw and swap all its USDC for ETH
        assertEq(baseToken.balanceOf(address(maker)), 1e9, "maker base token");
        assertEq(collateralToken.balanceOf(address(maker)), 0, "maker collateral token");
        assertEq(collateralToken.balanceOf(address(vault)), 988.040993e6, "vault collateral token");

        vm.stopPrank();
    }
}
