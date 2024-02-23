// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { BaseTest } from "../BaseTest.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { IUniswapV3Factory } from "../../src/external/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { SpotHedgeBaseMakerSpecSetup } from "./SpotHedgeBaseMakerSpecSetup.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SpotHedgeBaseMakerHarness is SpotHedgeBaseMaker {
    SpotHedgeBaseMaker public maker;

    constructor() SpotHedgeBaseMaker() {}

    function exposed_getSpotHedgeBaseMakerStorage()
        private
        pure
        returns (SpotHedgeBaseMaker.SpotHedgeBaseMakerStorage storage $)
    {
        assembly {
            $.slot := _SPOT_HEDGE_BASE_MAKER_STORAGE_LOCATION
        }
    }

    function exposed_uniswapV3Router() external view returns (ISwapRouter) {
        return exposed_getSpotHedgeBaseMakerStorage().uniswapV3Router;
    }

    function exposed_uniswapV3Factory() external view returns (IUniswapV3Factory) {
        return exposed_getSpotHedgeBaseMakerStorage().uniswapV3Factory;
    }

    function exposed_uniswapV3PathMap(bytes32 key) external view returns (bytes memory) {
        return exposed_getSpotHedgeBaseMakerStorage().uniswapV3PathMap[key];
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract SpotHedgeBaseMakerInitialize is SpotHedgeBaseMakerSpecSetup {
    function setUp() public override {
        SpotHedgeBaseMakerSpecSetup.setUp();
    }

    function test_initialize_Normal() public {
        SpotHedgeBaseMakerHarness maker = new SpotHedgeBaseMakerHarness();
        _enableInitialize(address(maker));
        maker.initialize(
            0,
            name,
            symbol,
            mockAddressManager,
            uniswapV3Router,
            uniswapV3Factory,
            uniswapV3Quoter,
            address(baseToken),
            1e18
        );

        assertEq(maker.marketId(), 0);
        assertEq(maker.name(), name);
        assertEq(maker.symbol(), symbol);
        assertEq(address(maker.baseToken()), address(baseToken));
        assertEq(address(maker.quoteToken()), address(quoteToken));
        assertEq(address(maker.exposed_uniswapV3Router()), uniswapV3Router);
        assertEq(address(maker.exposed_uniswapV3Factory()), uniswapV3Factory);
    }

    function test_construct_RevertIf_DisableInitialize() public {
        SpotHedgeBaseMaker maker = new SpotHedgeBaseMaker();

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        maker.initialize(
            0,
            name,
            symbol,
            mockAddressManager,
            uniswapV3Router,
            uniswapV3Factory,
            uniswapV3Quoter,
            address(baseToken),
            1e18
        );
    }
}
