// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { LibError } from "../../src/common/LibError.sol";
import { IVault } from "../../src/vault/IVault.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { WhitelistLpManager, IWhitelistLpManager } from "../../src/maker/WhitelistLpManager.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { TestCustomDecimalsToken } from "../helper/TestCustomDecimalsToken.sol";
import { FakeUniswapV3Router } from "../helper/FakeUniswapV3Router.sol";
import { FakeUniswapV3Factory } from "../helper/FakeUniswapV3Factory.sol";
import { FakeUniswapV3Quoter } from "../helper/FakeUniswapV3Quoter.sol";
import "../BaseTest.sol";

contract WhitelistLpWithOMInt is BaseTest {
    WhitelistLpManager public whitelistLpManager;
    OracleMaker public oracleMaker;

    address public lp = makeAddr("LiquidityProvider");
    address public mockedAddressManager = makeAddr("MockedAddressManager");
    address public mockedPythOracleAdapter = makeAddr("MockedPythOracleAdapter");

    function setUp() public {
        whitelistLpManager = new WhitelistLpManager();
        oracleMaker = new OracleMaker();

        vm.mockCall(
            mockedAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, WHITELIST_LP_MANAGER),
            abi.encode(address(whitelistLpManager))
        );
        vm.mockCall(
            mockedAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, PYTH_ORACLE_ADAPTER),
            abi.encode(mockedPythOracleAdapter)
        );
        vm.mockCall(
            mockedPythOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.priceFeedExists.selector),
            abi.encode(true)
        );

        _enableInitialize(address(oracleMaker));
        oracleMaker.initialize(0, "OM", "OM", address(mockedAddressManager), 0, 1e18);
    }

    function test_deposit_RevertIfLpIsNotWhitelisted() public {
        vm.prank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        oracleMaker.deposit(1);
    }

    function test_withdraw_RevertIfLpIsNotWhitelisted() public {
        vm.prank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        oracleMaker.withdraw(1);
    }
}

contract WhitelistLpWithSHBMInt is BaseTest {
    WhitelistLpManager public whitelistLpManager;
    SpotHedgeBaseMaker public spotHedgeBaseMaker;

    address public lp = makeAddr("LiquidityProvider");
    address public mockedAddressManager = makeAddr("MockedAddressManager");
    address public mockedVault = makeAddr("MockedVault");
    string public name = "SHBMName";
    string public symbol = "SHBMSymbol";
    TestCustomDecimalsToken public baseToken;
    TestCustomDecimalsToken public quoteToken;

    FakeUniswapV3Router public uniswapV3Router;
    FakeUniswapV3Factory public uniswapV3Factory;
    FakeUniswapV3Quoter public uniswapV3Quoter;

    function setUp() public {
        whitelistLpManager = new WhitelistLpManager();
        spotHedgeBaseMaker = new SpotHedgeBaseMaker();
        baseToken = new TestCustomDecimalsToken("testETH", "testETH", 9);
        quoteToken = new TestCustomDecimalsToken("testQuote", "testQuote", 18);
        uniswapV3Router = new FakeUniswapV3Router();
        uniswapV3Factory = new FakeUniswapV3Factory();
        uniswapV3Quoter = new FakeUniswapV3Quoter();

        vm.mockCall(
            mockedAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, WHITELIST_LP_MANAGER),
            abi.encode(address(whitelistLpManager))
        );
        vm.mockCall(
            mockedAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, VAULT),
            abi.encode(address(mockedVault))
        );
        vm.mockCall(
            mockedVault,
            abi.encodeWithSelector(IVault.getCollateralToken.selector),
            abi.encode(address(quoteToken))
        );

        _enableInitialize(address(spotHedgeBaseMaker));
        spotHedgeBaseMaker.initialize(
            0, // marketId
            name,
            symbol,
            address(mockedAddressManager),
            address(uniswapV3Router),
            address(uniswapV3Factory),
            address(uniswapV3Quoter),
            address(baseToken),
            0.5e18
        );
    }

    function test_deposit_RevertIfLpIsNotWhitelisted() public {
        vm.prank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        spotHedgeBaseMaker.deposit(1);
    }

    function test_withdraw_RevertIfLpIsNotWhitelisted() public {
        vm.prank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        spotHedgeBaseMaker.withdraw(1);
    }
}
