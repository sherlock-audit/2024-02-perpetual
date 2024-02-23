// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { IUniswapV3Factory } from "../../src/external/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { TestCustomDecimalsToken } from "../helper/TestCustomDecimalsToken.sol";
import "../MockSetup.sol";

contract SpotHedgeBaseMakerSpecSetup is MockSetup {
    string public name = "SHBMName";
    string public symbol = "SHBMSymbol";
    address public uniswapV3Router = makeAddr("UniswapV3Router");
    address public uniswapV3Factory = makeAddr("UniswapV3Factory");
    address public uniswapV3Quoter = makeAddr("UniswapV3Quoter");
    TestCustomDecimalsToken public baseToken;
    TestCustomDecimalsToken public quoteToken;

    bytes public uniswapV3B2QPath;
    bytes public uniswapV3Q2BPath;
    address public uniswapV3SpotPool = makeAddr("UniswapV3SpotPool");

    function setUp() public virtual override {
        MockSetup.setUp();
        init(address(new TestCustomDecimalsToken("testETH", "testETH", 9))); // Deliberately different from WETH so we could test decimal conversions.
    }

    function init(address baseTokenArg) public virtual {
        baseToken = TestCustomDecimalsToken(baseTokenArg);
        vm.label(address(baseToken), baseToken.symbol());
        quoteToken = new TestCustomDecimalsToken("USDC", "USDC", 6);
        vm.label(address(quoteToken), quoteToken.symbol());

        uniswapV3B2QPath = abi.encodePacked(address(baseToken), uint24(3000), address(quoteToken));
        uniswapV3Q2BPath = abi.encodePacked(address(quoteToken), uint24(3000), address(baseToken));

        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.getPriceFeedId.selector, marketId),
            abi.encode(priceFeedId)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getCollateralToken.selector),
            abi.encode(address(quoteToken))
        );
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function _create_Maker() internal returns (SpotHedgeBaseMaker) {
        SpotHedgeBaseMaker maker = new SpotHedgeBaseMaker();
        _enableInitialize(address(maker));
        maker.initialize(
            marketId,
            name,
            symbol,
            mockAddressManager,
            uniswapV3Router,
            uniswapV3Factory,
            uniswapV3Quoter,
            address(baseToken),
            1e18
        );

        // Mock UniswapV3Factory so _verifyPath() can pass
        vm.mockCall(
            address(uniswapV3Factory),
            abi.encodeWithSelector(
                IUniswapV3Factory.getPool.selector,
                address(baseToken),
                address(quoteToken),
                uint24(3000)
            ),
            abi.encode(uniswapV3SpotPool)
        );
        vm.mockCall(
            address(uniswapV3Factory),
            abi.encodeWithSelector(
                IUniswapV3Factory.getPool.selector,
                address(quoteToken),
                address(baseToken),
                uint24(3000)
            ),
            abi.encode(uniswapV3SpotPool)
        );

        maker.setUniswapV3Path(address(baseToken), address(quoteToken), uniswapV3B2QPath);
        maker.setUniswapV3Path(address(quoteToken), address(baseToken), uniswapV3Q2BPath);

        return maker;
    }

    function _mockUniswapV3RouterExactInput(
        address maker,
        bytes memory path,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        vm.mockCall(
            address(uniswapV3Router),
            abi.encodeWithSelector(
                ISwapRouter.exactInput.selector,
                ISwapRouter.ExactInputParams({
                    path: path,
                    recipient: maker,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0
                })
            ),
            abi.encode(amountOut)
        );
    }

    function _mockUniswapV3RouterExactOutput(
        address maker,
        bytes memory path,
        uint256 amountOut,
        uint256 amountIn
    ) internal {
        vm.mockCall(
            address(uniswapV3Router),
            abi.encodeWithSelector(
                ISwapRouter.exactOutput.selector,
                ISwapRouter.ExactOutputParams({
                    path: path,
                    recipient: maker,
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: type(uint256).max
                })
            ),
            abi.encode(amountIn)
        );
    }
}
