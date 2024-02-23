// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../clearingHouse/ClearingHouseIntSetup.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { TestCustomDecimalsToken } from "../helper/TestCustomDecimalsToken.sol";
import { FakeUniswapV3Router } from "../helper/FakeUniswapV3Router.sol";
import { FakeUniswapV3Factory } from "../helper/FakeUniswapV3Factory.sol";
import { FakeUniswapV3Quoter } from "../helper/FakeUniswapV3Quoter.sol";

// Note the setup does not include Uniswap system due to a few technical limitation.
// For Uniswap-related tests we use fork-test instead (SpotHedgeBaseMakerForkSetup).
contract SpotHedgeBaseMakerIntSetup is ClearingHouseIntSetup {
    address public makerLp = makeAddr("MakerLP");

    string public name = "SHBMName";
    string public symbol = "SHBMSymbol";
    TestCustomDecimalsToken public baseToken;

    FakeUniswapV3Router public uniswapV3Router;
    FakeUniswapV3Factory public uniswapV3Factory;
    FakeUniswapV3Quoter public uniswapV3Quoter;

    uint24 public spotPoolFee = 3000;
    address public spotPool = makeAddr("SpotPool");

    bytes public uniswapV3B2QPath;
    bytes public uniswapV3Q2BPath;

    SpotHedgeBaseMaker public maker;

    function setUp() public virtual override {
        baseToken = new TestCustomDecimalsToken("testETH", "testETH", 9);
        vm.label(address(baseToken), baseToken.symbol());
        // Deliberately different from WETH so we could test decimal conversions.

        ClearingHouseIntSetup.setUp();
        _setCollateralTokenAsCustomDecimalsToken(6);

        //
        // Provision fake Uniswap system
        //

        uniswapV3Router = new FakeUniswapV3Router();
        uniswapV3Factory = new FakeUniswapV3Factory();
        uniswapV3Quoter = new FakeUniswapV3Quoter();

        deal(address(baseToken), address(uniswapV3Router), 1e36, true);
        deal(address(collateralToken), address(uniswapV3Router), 100 * 1e36, true);

        uniswapV3Factory.setPool(address(baseToken), address(collateralToken), spotPoolFee, spotPool);
        uniswapV3Factory.setPool(address(collateralToken), address(baseToken), spotPoolFee, spotPool);

        //
        // Provision the maker
        //

        uniswapV3B2QPath = abi.encodePacked(address(baseToken), uint24(spotPoolFee), address(collateralToken));

        uniswapV3Q2BPath = abi.encodePacked(address(collateralToken), uint24(spotPoolFee), address(baseToken));

        config.createMarket(marketId, priceFeedId);
        maker = new SpotHedgeBaseMaker();
        _enableInitialize(address(maker));
        maker.initialize(
            marketId,
            name,
            symbol,
            address(addressManager),
            address(uniswapV3Router),
            address(uniswapV3Factory),
            address(uniswapV3Quoter),
            address(baseToken),
            0.5e18
        );
        config.registerMaker(marketId, address(maker));

        maker.setUniswapV3Path(address(baseToken), address(collateralToken), uniswapV3B2QPath);
        maker.setUniswapV3Path(address(collateralToken), address(baseToken), uniswapV3Q2BPath);
    }

    function _provisionMakerForFillOrder() internal {
        // Prepare collaterals for maker
        vm.startPrank(makerLp);

        // Deposit plenty of base token for maker
        deal(address(baseToken), address(makerLp), 1e36, true);
        baseToken.approve(address(maker), type(uint256).max);
        maker.deposit(1e36);

        vm.stopPrank();

        // Deposit plenty of collateral token for maker
        _deposit(marketId, address(maker), 1e36);
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
