// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../oracleMaker/OracleMakerIntSetup.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { CircuitBreaker } from "../../src/circuitBreaker/CircuitBreaker.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { LibError } from "../../src/common/LibError.sol";

contract CircuitBreakerOracleMakerInt is OracleMakerIntSetup {
    CircuitBreaker circuitBreaker;

    address admin = makeAddr("admin");
    address trader = makeAddr("trader");

    function setUp() public virtual override {
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
        circuitBreaker.registerAsset(address(collateralToken), 7000, 0);
        circuitBreaker.addProtectedContracts(protectedContracts);
        vm.stopPrank();

        // set the address of CircuitBreaker
        addressManager.setAddress(CIRCUIT_BREAKER, address(circuitBreaker));

        _mockPythPrice(100, 0);

        deal(address(collateralToken), trader, 1000e6, true);

        // NOTE: must do to avoid the initial block.timestamp to be 0
        vm.warp(5 hours);
    }

    function test_RevertIf_OracleMakerWithdrawRateLimited() public {
        vm.startPrank(trader);
        collateralToken.approve(address(maker), 1000e6);
        uint256 shares = maker.deposit(1000e6);

        skip(4 hours);

        // withdraw all shares should revert
        vm.expectRevert(abi.encodeWithSelector(LibError.RateLimited.selector));
        maker.withdraw(shares);

        // withdraw a little shares should succeed
        maker.withdraw(shares / 10);

        vm.stopPrank();
    }
}
