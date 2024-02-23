// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;
pragma abicoder v2;

import { CircuitBreaker } from "../../src/circuitBreaker/CircuitBreaker.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { VaultSpecSetup } from "../vault/VaultSpecSetup.sol";
import { LibError } from "../../src/common/LibError.sol";

contract CircuitBreakerSpec is VaultSpecSetup {
    CircuitBreaker circuitBreaker;

    address admin = makeAddr("admin");
    address trader = makeAddr("trader");
    address nonProtectedContract = makeAddr("nonProtectedContract");

    // test 5: maker withdraw hit rate limit

    function setUp() public override {
        super.setUp();

        // _rateLimitCooldownPeriod
        // _withdrawalPeriod
        // _liquidityTickLength
        circuitBreaker = new CircuitBreaker(admin, 3 days, 4 hours, 5 minutes);

        address[] memory protectedContracts = new address[](1);
        protectedContracts[0] = address(vault);

        vm.startPrank(admin);
        // _minLiqRetainedBps: 7000 == 70%
        // _limitBeginThreshold
        circuitBreaker.registerAsset(collateralToken, 7000, 0);
        circuitBreaker.addProtectedContracts(protectedContracts);
        vm.stopPrank();

        // NOTE: must do to avoid the initial block.timestamp to be 0
        vm.warp(5 hours);

        // override the address of CircuitBreaker in super.setUp()
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, "CircuitBreaker"),
            abi.encode(address(circuitBreaker))
        );

        _mintAndApproveVault(trader, 10000e6);
    }

    function test_TokenLimiters() public {
        vm.startPrank(trader);
        vault.deposit(trader, 1000e6);

        {
            (, , int256 liqTotal, int256 liqInPeriod, uint256 listHead, ) = circuitBreaker.tokenLimiters(
                collateralToken
            );
            assertEq(liqTotal, 0); // liqTotal: total change from 0h ~ 1h is 0
            assertEq(liqInPeriod, 1000e6); // liqInPeriod: total change from 1h ~ 5h is +1000 (deposit)
            assertEq(listHead, 5 hours);
        }

        skip(6 hours);

        vault.deposit(trader, 2000e6);

        {
            (, , int256 liqTotal, int256 liqInPeriod, uint256 listHead, ) = circuitBreaker.tokenLimiters(
                collateralToken
            );
            assertEq(liqTotal, 1000e6); // liqTotal: total change from 0h ~ 7h is 1000
            assertEq(liqInPeriod, 2000e6); // liqInPeriod: total change from 7h ~ 11h is +2000 (deposit)
            assertEq(listHead, 11 hours);
        }

        skip(6 hours);

        vault.withdraw(300e6);

        {
            (, , int256 liqTotal, int256 liqInPeriod, uint256 listHead, ) = circuitBreaker.tokenLimiters(
                collateralToken
            );
            assertEq(liqTotal, 3000e6); // liqTotal: total change from 0h ~ 13h is 3000
            assertEq(liqInPeriod, -300e6); // liqInPeriod: total change from 13h ~ 17h is -300 (deposit)
            assertEq(listHead, 17 hours);
        }
        vm.stopPrank();
    }

    function test_Withdraw_InSamePeriod() public {
        vm.startPrank(trader);

        // deposit and withdraw in one period makes liqInPeriod = 0
        // so futureLiq == currentLiq (liqTotal)
        vault.deposit(trader, 1000e6);

        vm.expectEmit(true, true, true, true, address(collateralToken));
        emit IERC20.Transfer(address(circuitBreaker), address(trader), 1000e6);
        vault.withdraw(1000e6);

        vm.stopPrank();
    }

    function test_Withdraw_InSamePeriodNearEdge() public {
        vm.startPrank(trader);

        vault.deposit(trader, 1000e6);

        skip(4 hours - 1);

        vm.expectEmit(true, true, true, true, address(collateralToken));
        emit IERC20.Transfer(address(circuitBreaker), address(trader), 1000e6);
        vault.withdraw(1000e6);

        vm.stopPrank();
    }

    function test_Withdraw_LimitBeginThresholdIsSet() public {
        vm.prank(admin);
        circuitBreaker.updateAssetParams(collateralToken, 7000, 10000e6);

        (, uint256 limitBeginThreshold, , , , ) = circuitBreaker.tokenLimiters(collateralToken);
        assertEq(limitBeginThreshold, 10000e6);

        vm.startPrank(trader);

        vault.deposit(trader, 1000e6);

        skip(4 hours);

        // liqTotal = 1000, so minLiq = 700, can only withdraw amount <= 300
        // futureLiq = liqTotal + liqInPeriod = 1000 + -301 = 699
        // futureLiq < minLiq => 699 < 700 => trigger rate limit
        // should not revert because it is not activated yet
        vm.expectEmit(true, true, true, true, address(collateralToken));
        emit IERC20.Transfer(address(circuitBreaker), address(trader), 301e6);
        vault.withdraw(301e6);

        vm.stopPrank();

        // currently liqTotal = 1000, so limitBeginThreshold set to 1000 should acivate circuit breaker
        vm.prank(admin);
        circuitBreaker.updateAssetParams(collateralToken, 7000, 1000e6);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(LibError.RateLimited.selector));
        // liqInPeriod = -301 + -300 = -601
        // futureLiq = 1000 - 601 = 399, minLiq = 700 => should revert
        vault.withdraw(300e6);
    }

    function test_Withdraw_RevertIf_RateLimited() public {
        vm.startPrank(trader);
        vault.deposit(trader, 1000e6);

        skip(4 hours);

        vm.expectRevert(abi.encodeWithSelector(LibError.RateLimited.selector));
        // liqTotal = 1000, so minLiq = 700, can only withdraw amount <= 300
        // futureLiq = liqTotal + liqInPeriod = 1000 + -301 = 699
        // futureLiq < minLiq => 699 < 700 => trigger rate limit
        vault.withdraw(301e6);

        // futureLiq = liqTotal + liqInPeriod = 1000 + -300 = 700
        // futureLiq < minLiq => 700 >= 700 => pass
        vault.withdraw(300e6);

        // withdraw 1 should revert
        vm.expectRevert(abi.encodeWithSelector(LibError.RateLimited.selector));
        vault.withdraw(1e6);

        skip(4 hours);

        // minLiq = 700 * 0.7 = 490
        // max withdraw = 700 - 490 = 210
        vm.expectRevert(abi.encodeWithSelector(LibError.RateLimited.selector));
        vault.withdraw(211e6);

        vault.withdraw(210e6);

        vm.stopPrank();
    }

    function test_OnTokenInflow_RevertIf_NotAProtectedContract() public {
        vm.prank(nonProtectedContract);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAProtectedContract.selector));
        circuitBreaker.onTokenInflow(collateralToken, 1000e6);
    }

    function test_OnTokenOutflow_RevertIf_NotAProtectedContract() public {
        vm.prank(nonProtectedContract);
        vm.expectRevert(abi.encodeWithSelector(LibError.NotAProtectedContract.selector));
        circuitBreaker.onTokenOutflow(collateralToken, 1000e6, trader, true);
    }

    function _mintAndApproveVault(address wallet, uint256 amount) internal {
        deal(collateralToken, wallet, amount, true);

        vm.prank(wallet);
        ERC20(collateralToken).approve(address(vault), amount);
    }
}
