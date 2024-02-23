// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../spotHedgeMaker/SpotHedgeBaseMakerIntSetup.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { CircuitBreaker } from "../../src/circuitBreaker/CircuitBreaker.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { LibError } from "../../src/common/LibError.sol";

contract CircuitBreakerSpotHedgeBaseMakerInt is SpotHedgeBaseMakerIntSetup {
    address admin = makeAddr("admin");
    address trader = makeAddr("trader");

    function setUp() public virtual override {
        super.setUp();

        // setup maker
        // Prepare collaterals for maker
        vm.startPrank(makerLp);

        // Deposit plenty of base token for maker
        deal(address(baseToken), address(makerLp), 1e9, true);
        baseToken.approve(address(maker), type(uint256).max);
        maker.deposit(1e9);

        vm.stopPrank();

        // Deposit plenty of collateral token for maker
        _deposit(marketId, address(maker), 1e9);

        // _rateLimitCooldownPeriod
        // _withdrawalPeriod
        // _liquidityTickLength
        CircuitBreaker circuitBreaker = new CircuitBreaker(admin, 3 days, 4 hours, 5 minutes);

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

    function test_RevertIf_WithdrawRateLimited_WhenMakerFillOrder() public {
        vm.startPrank(trader);

        collateralToken.approve(address(vault), 5e6);
        vault.deposit(trader, 5e6);
        vault.transferFundToMargin(marketId, 5e6);

        // Price = $100
        // Fake uniswap router behavior.
        uniswapV3Router.setAmountOut(
            ISwapRouter.ExactInputParams({
                path: uniswapV3B2QPath,
                recipient: address(maker),
                deadline: block.timestamp,
                amountIn: 0.5e9, // 0.5 TestETH
                amountOutMinimum: 0
            }),
            50e6 // 50 USDC
        );

        // taker short 0.5 ether (50 USDC), maker deposit 50 USDC to vault
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: true,
                isExactInput: true,
                amount: 0.5 ether,
                oppositeAmountBound: 0,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        skip(4 hours);

        // Fake uniswap quoter behavior: quote exact output 0.5 TestETH and get 50 USDC amountIn
        uniswapV3Quoter.setAmountIn(uniswapV3B2QPath, 0.5e9, 50e6);

        // Fake uniswap router behavior.
        uniswapV3Router.setAmountIn(
            ISwapRouter.ExactOutputParams({
                path: uniswapV3Q2BPath,
                recipient: address(maker),
                deadline: block.timestamp,
                amountOut: 0.5e9, // 0.5 TestETH
                amountInMaximum: type(uint256).max
            }),
            50e6 // 50 USDC
        );

        // taker long 0.5 ether, maker withdraw 50 USDC from vault
        // tvl = maker deposit 50 USDC + taker deposit 5 USDC = 55 USDC
        // withdraw 50 USDC should revert
        vm.expectRevert(abi.encodeWithSelector(LibError.RateLimited.selector));
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: address(maker),
                isBaseToQuote: false,
                isExactInput: false,
                amount: 0.5 ether,
                oppositeAmountBound: 150 ether,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        vm.stopPrank();
    }
}
