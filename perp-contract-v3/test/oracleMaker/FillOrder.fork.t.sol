// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./OracleMakerForkSetup.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";

contract OracleMakerFillOrderFork is OracleMakerForkSetup {
    address public taker = makeAddr("taker");

    function setUp() public override {
        super.setUp();
        _deposit(marketId, taker, 1000e6);
        _deposit(marketId, address(maker), 2000e6);
    }

    function test_fillOrder_Normal() public {
        address[] memory targets = new address[](2);
        targets[0] = address(pythOracleAdapter);
        targets[1] = address(clearingHouse);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IPythOracleAdapter.updatePrice.selector, ethUsdPriceFeedId, priceUpdateData);
        data[1] = abi.encodeWithSelector(
            IClearingHouse.openPosition.selector,
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: true,
                amount: 1500 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: priceUpdateData
            })
        );

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        // update price before opening position
        // taker long ether with 1500 usd
        vm.prank(maker.owner());
        maker.setValidSender(address(multicallerWithSender), true);

        vm.prank(taker);
        multicallerWithSender.aggregateWithSender(targets, data, values);

        _assertEq(
            _getMarginProfile(marketId, taker, 0), // assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: 816685427745798493, // 1500 / 1836.6925 = 0.8166854277
                openNotional: -1500 ether,
                accountValue: -500 ether,
                unrealizedPnl: -1500 ether,
                freeCollateral: 0,
                freeCollateralForOpen: -650 ether, // min(1000, -500) - 1500 * 0.1 = -650
                freeCollateralForReduce: -593.75 ether, // min(1000, -500) - 1500 * 0.0625 = -593.75
                marginRatio: -0.333333333333333333 ether // -500/1500=0.33
            })
        );
        _assertEq(
            _getMarginProfile(marketId, address(maker), 0), // assign price = 0 since we don't care about account value atm
            LegacyMarginProfile({
                positionSize: -816685427745798493,
                openNotional: 1500 ether,
                accountValue: 3500 ether,
                unrealizedPnl: 1500 ether,
                freeCollateral: 1850 ether,
                freeCollateralForOpen: 1850 ether, // min(2000, 3500) - 1500 * 0.1 = 1850
                freeCollateralForReduce: 1906.25 ether, // min(2000, 3500) - 1500 * 0.0625 = 1906.25
                marginRatio: 2.333333333333333333 ether // 3500/1500=2.33
            })
        );
        vm.stopPrank();
    }
}
