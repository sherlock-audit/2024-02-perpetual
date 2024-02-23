// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../clearingHouse/ClearingHouseIntSetup.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { IUniswapV3Factory } from "../../src/external/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3PoolActions } from "../../src/external/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import { IUniswapV3PoolImmutables } from "../../src/external/uniswap-v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import { ISwapRouter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IQuoter } from "../../src/external/uniswap-v3-periphery/contracts/interfaces/IQuoter.sol";
import { TestCustomDecimalsToken } from "../helper/TestCustomDecimalsToken.sol";
import { TestWETH9 } from "../helper/TestWETH9.sol";
import { INonfungiblePositionManager } from "./INonfungiblePositionManager.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";

contract SpotHedgeBaseMakerForkSetup is ClearingHouseIntSetup {
    uint256 forkBlock = 105_302_472; // Optimiam mainnet @ Thu Jun  8 05:55:21 UTC 2023

    address public makerLp = makeAddr("MakerLP");
    address public spotLp = makeAddr("SpotLP");

    string public name = "SHBMName";
    string public symbol = "SHBMSymbol";
    TestWETH9 public weth;
    TestCustomDecimalsToken public baseToken;

    // Optimism Mainnet
    ISwapRouter public uniswapV3Router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Uniswap v3 Swap Router v1 @ Optimism Mainnet
    IUniswapV3Factory public uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984); // Uniswap v3 Factory @ Optimism Mainnet
    IQuoter public uniswapV3Quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6); // Uniswap v3 Quoter v1 @ Optimism Mainnet
    INonfungiblePositionManager public uniswapV3NonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    bytes public uniswapV3B2QPath;
    bytes public uniswapV3Q2BPath;
    address public uniswapV3SpotPool;

    // Fetched around the same time of forkBlock. The price timestamp must be within 60 secs. from the block timestamp
    // to avoid Pyth.StalePrice() error.
    //
    // $ curl https://xc-mainnet.pyth.network/api/latest_vaas?ids[]=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
    // ["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"]
    //
    // above price = 1836.6925
    //
    // Converted by Buffer.from(vaas_str_above, "base64").toString("hex")
    bytes public priceUpdateData =
        hex"01000000030d00c2dfc7626e7076b83f19fc5bca281d3c241729ef369b135e3081afcacf856c696fdae82a2b1ed4ddfc14a667d6a7348ab8c6f2fdf0becc4e0577e37b71b73fe50101b438a63525b8f5d54b3947cc0404073f53cc24ea852fcbd2d56a1591c4f3e30456da37ded2cfb57f896b2f96444cae02838a70575cfbc102e600b070afa9e27d000265cdfbbc26cd8c5a1dceb5caba526bacd706a523ef961bae56a7f45d572e2e22499d0f920267b053545cb4e7c441dd3129d671ef494a7208e9c3134944539bde0004f5c1588e839c930bdc4d2e7c7e6b6bc659b0f2a4a0ad5d7f12140170ec7e32630f87424945880dae481005be935c8a479add63711c452937ae278ff68bd23d5a0106b9bc81d31511a03ab4f36e9fe5d9b8dd95be083967fad01c0174b960185959cc4da89357995efd6c29fd94d4c54e581ee52349ba14e7d1901b82a250b008d8f700095fae6f46953a46d1556b1400f4afc899bdf522a6396b9833cbe864da6a614c8e3cf109c651d896a48ce94159f1f5e6c37937cefb1032489223dc7b3c6c0df40f010a8af3499aadd61ddfaa0ec4abb9a08a12edce8fc54837b90c68344dcba1cf9b2442208e11b79f77cab15a6fa0901b8bb5ee99e653190e17695afdb8dba452ae03010ba0c63e50c205d5d87e218521673d7944b94f5a06dc6925ea726d25876a9c24cc753eb5abc2f932a67f5884f705ba03c66745b0aad1f6d04a455f76e826394e40010d0486e73d19b5e55144ad08cee2337185eba4e79353528a9bb42b922aa1d5e8be5f197a74ab06064bbf9a4e0c4c1c9b658f75d81d36c546c3caa73d1e2eac0570010e93816517a08ed4ceb404c41f56c1a0ab769667d6a023d71e4057697dbcd475f159a54ce7a80fdeec8e3f0bea5cb8767648514ba801ec55fc4724d0f96531ed15000f8ce5c6b4cb93dfbad4336ab270dc3365d8903bf340687c08be5230461011974325afe1e02042b64f48c9beae8c4854f7b12569184fa4c9e445506bd3a13871b20011f46645418821afbf7bf69e95cc07c80f1b5d254b8e561d04ce88f08e8719161d7258c8e30ce3cbae425516f4a60c30cb9313dd0545e385911a601461e03d90500012e31a8e7fbd8a81c8f1e8a2b1a6f743b8a901fc7bdc2b486aa9f2d15c300d16f938028165aca84b5bc01e63409ef80335aa2569484590d4c7e2f9a987e61a67f90164816d4500000000001af8cd23c2ab91237730770bbea08d61005cdda0984348f3f6eecb559638c0bba0000000001b85a2b50150325748000300010001020005009d04028fba493a357ecde648d51375a445ce1cb9681da1ea11e562b53522a5d3877f981f906d7cfe93f618804f1de89e0199ead306edc022d3230b3e8305f391b00000002a9e84375f000000000e7a7d61fffffff80000002aa6a23250000000000e3b3f37010000000a0000000c0000000064816d450000000064816d450000000064816d440000002a9e84375f000000000e7a7d610000000064816d44e6c020c1a15366b779a8c870e065023657c88c82b82d58a9fe856896a4034b0415ecddd26d49e1a8f1de9376ebebc03916ede873447c1255d2d5891b92ce57170000002c572b0c400000000009a7ec80fffffff80000002c5f098748000000000a0579370100000007000000080000000064816d450000000064816d450000000064816d440000002c57236b200000000009a04b600000000064816d44c67940be40e0cc7ffaa1acb08ee3fab30955a197da1ec297ab133d4d43d86ee6ff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace0000002ac38a57d00000000004d9a8adfffffff80000002acd333e5000000000045471570100000018000000200000000064816d450000000064816d450000000064816d440000002ac38a57d00000000004d9a8ad0000000064816d448d7c0971128e8a4764e757dedb32243ed799571706af3a68ab6a75479ea524ff846ae1bdb6300b817cee5fdee2a6da192775030db5615b94a465f53bd40850b50000002abcc96d4c000000000bc27de1fffffff80000002ac30d8e800000000014a8c71c01000000080000000a0000000064816d450000000064816d450000000064816d440000002abcc96d4c000000000bc27de10000000064816d44543b71a4c292744d3fcf814a2ccda6f7c00f283d457f83aa73c41e9defae034ba0255134973f4fdf2f8f7808354274a3b1ebc6ee438be898d045e8b56ba1fe1300000000000000000000000000000000fffffff8000000000000000000000000000000000000000000000000080000000064816d450000000064816d410000000000000000000000000000000000000000000000000000000000000000";

    SpotHedgeBaseMaker public maker;

    function setUp() public virtual override {
        vm.label(address(uniswapV3Router), "UniswapV3Router");
        vm.label(address(uniswapV3Factory), "UniswapV3Factory");
        vm.label(address(uniswapV3Quoter), "UniswapV3Quoter");
        vm.label(address(uniswapV3NonfungiblePositionManager), "UniswapV3NonfungiblePositionManager");
        vm.createSelectFork(vm.rpcUrl("optimism"), forkBlock);

        ClearingHouseIntSetup.setUp();
        _setCollateralTokenAsCustomDecimalsToken(6);
        vm.label(address(collateralToken), collateralToken.symbol());

        // disable borrwoing fee
        config.setMaxBorrowingFeeRate(marketId, 0, 0);

        // use forkPyth
        _deployPythOracleAdaptorInFork();

        // NOTE: Changes above might impact token0, token1 ordering in the Uniswap pool.
        baseToken = new TestCustomDecimalsToken("testETH", "testETH", 9); // Deliberately different from WETH so we could test decimal conversions.
        vm.label(address(baseToken), baseToken.symbol());

        uint24 spotPoolFee = 3000;

        uniswapV3B2QPath = abi.encodePacked(address(baseToken), uint24(spotPoolFee), address(collateralToken));

        uniswapV3Q2BPath = abi.encodePacked(address(collateralToken), uint24(spotPoolFee), address(baseToken));

        deal(address(baseToken), spotLp, 100e9, true);
        deal(address(collateralToken), spotLp, 200000e6, true);

        //
        // Provision Uniswap v3 system
        //

        uniswapV3SpotPool = uniswapV3Factory.createPool(address(baseToken), address(collateralToken), spotPoolFee);
        vm.label(uniswapV3SpotPool, "UniswapV3SpotPool");

        // spot price ~= $2000
        uint160 spotPoolInitSqrtPriceX96;
        if (address(baseToken) < address(collateralToken)) {
            spotPoolInitSqrtPriceX96 = 1.1204554194957229E29; // sqrt(2000e6 / 1e9) * 2^96 (assume token0 = baseToken, token1 = quoteToken)
        } else {
            spotPoolInitSqrtPriceX96 = 5.602277097478614E28; // sqrt(1e9 / 2000e6) * 2^96 (assume token1 = baseToken, token0 = quoteToken)
        }
        IUniswapV3PoolActions(uniswapV3SpotPool).initialize(spotPoolInitSqrtPriceX96);
        IUniswapV3PoolActions(uniswapV3SpotPool).increaseObservationCardinalityNext(250);

        TestCustomDecimalsToken token0 = TestCustomDecimalsToken(IUniswapV3PoolImmutables(uniswapV3SpotPool).token0());
        TestCustomDecimalsToken token1 = TestCustomDecimalsToken(IUniswapV3PoolImmutables(uniswapV3SpotPool).token1());

        vm.startPrank(spotLp);
        token0.approve(address(uniswapV3NonfungiblePositionManager), type(uint256).max);
        token1.approve(address(uniswapV3NonfungiblePositionManager), type(uint256).max);
        // Provide full-range using all tokens spotLp has.
        uniswapV3NonfungiblePositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: spotPoolFee,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: token0.balanceOf(spotLp),
                amount1Desired: token1.balanceOf(spotLp),
                amount0Min: 0,
                amount1Min: 0,
                recipient: spotLp,
                deadline: block.timestamp
            })
        );
        vm.stopPrank();

        //
        // Provision the maker
        //

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
            // since margin ratio=accValue/openNotional instead of posValue, it can't maintain 1.0 most of the time
            // even when spotHedge always do 1x long
            0.5 ether
        );
        config.registerMaker(marketId, address(maker));

        maker.setUniswapV3Path(address(baseToken), address(collateralToken), uniswapV3B2QPath);
        maker.setUniswapV3Path(address(collateralToken), address(baseToken), uniswapV3Q2BPath);

        deal(address(baseToken), address(makerLp), 1e9, true);
        vm.startPrank(makerLp);
        baseToken.approve(address(maker), type(uint256).max);
        maker.deposit(1e9);
        vm.stopPrank();
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
