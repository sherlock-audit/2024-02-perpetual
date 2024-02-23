// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ClearingHouseIntSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";

contract DepositInt is ClearingHouseIntSetup {
    address taker = makeAddr("taker");

    function setUp() public virtual override {
        ClearingHouseIntSetup.setUp();
        _newMarketWithTestMaker(marketId);
    }

    function test_Deposit_Success() public {
        deal(address(collateralToken), address(taker), 20e6, true);

        vm.startPrank(taker);
        IERC20(collateralToken).approve(address(vault), 10e6);

        vm.expectCall(address(vault), abi.encodeWithSelector(Vault.deposit.selector, address(taker), 10e6));
        vault.deposit(taker, 10e6);
        vault.transferFundToMargin(marketId, 10e6);
        vm.stopPrank();

        // TODO: account value should increase
        _assertEq(
            _getMarginProfile(marketId, taker, 1000),
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 10 ether,
                unrealizedPnl: 0,
                freeCollateral: 10 ether,
                freeCollateralForOpen: 10 ether, // min(10, 10) - 0 = 10
                freeCollateralForReduce: 10 ether, // min(10, 10) - 0 = 10
                marginRatio: 57896044618658097711785492504343953926634992332820282019728792003956564819967
            })
        );

        assertEq(collateralToken.balanceOf(taker), 10e6);
        assertEq(collateralToken.balanceOf(address(vault)), 10e6);
    }
}
