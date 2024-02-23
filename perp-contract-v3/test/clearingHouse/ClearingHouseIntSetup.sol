// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "../../src/clearingHouse/ClearingHouse.sol";
import "../../src/vault/IPositionModelEvent.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { MulticallerWithSender } from "multicaller/MulticallerWithSender.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { Config } from "../../src/config/Config.sol";
import { SystemStatus } from "../../src/systemStatus/SystemStatus.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { FundingFee } from "../../src/fundingFee/FundingFee.sol";
import { TestBorrowingFee } from "../helper/TestBorrowingFee.sol";
import { TestMaker } from "../helper/TestMaker.sol";
import { TestDeflationaryToken } from "../helper/TestDeflationaryToken.sol";
import { TestCustomDecimalsToken } from "../helper/TestCustomDecimalsToken.sol";
import { PythOracleAdapter } from "../../src/oracle/pythOracleAdapter/PythOracleAdapter.sol";
import { MakerReporter } from "../../src/makerReporter/MakerReporter.sol";

address constant MULTICALLER_WITH_SENDER = 0x00000000002Fd5Aeb385D324B580FCa7c83823A0;

contract ClearingHouseIntSetup is BaseTest {
    using FixedPointMathLib for int256;

    uint256 marketId = 0;
    ERC20 public collateralToken;
    TestDeflationaryToken public deflationaryCollateralToken;
    Vault public vault;
    ClearingHouse public clearingHouse;
    Config public config;
    SystemStatus public systemStatus;
    TestBorrowingFee public borrowingFee;
    FundingFee public fundingFee;
    IPyth public pyth = IPyth(makeAddr("Pyth"));
    bytes32 public priceFeedId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    PythOracleAdapter public pythOracleAdapter;
    AddressManager public addressManager;
    MulticallerWithSender public multicallerWithSender = MulticallerWithSender(payable(MULTICALLER_WITH_SENDER));
    MakerReporter public makerUtilRatioReporter;

    function setUp() public virtual {
        // external contact
        deflationaryCollateralToken = new TestDeflationaryToken("DF-USDC", "DF-USDC");
        collateralToken = ERC20(new TestCustomDecimalsToken("USDC", "USDC", 6));
        vm.label(address(collateralToken), collateralToken.symbol());

        // core contract
        addressManager = new AddressManager();

        vault = new Vault();
        _enableInitialize(address(vault));
        vault.initialize(address(addressManager), address(collateralToken));

        clearingHouse = new ClearingHouse();
        _enableInitialize(address(clearingHouse));
        clearingHouse.initialize(address(addressManager));

        config = new Config();
        _enableInitialize(address(config));
        config.initialize(address(addressManager));
        config.setMaxOrderValidDuration(3 minutes);
        config.setInitialMarginRatio(marketId, 0.1e18); // 10%
        config.setMaintenanceMarginRatio(marketId, 0.0625e18); // 6.25%
        config.setLiquidationFeeRatio(marketId, 0.5e18); // 50%
        config.setLiquidationPenaltyRatio(marketId, 0.025e18); // 2.5%
        config.setDepositCap(type(uint256).max); // allow maximum deposit

        systemStatus = new SystemStatus();
        _enableInitialize(address(systemStatus));
        systemStatus.initialize();

        borrowingFee = new TestBorrowingFee();
        _enableInitialize(address(borrowingFee));
        borrowingFee.initialize(address(addressManager));

        fundingFee = new FundingFee();
        _enableInitialize(address(fundingFee));
        fundingFee.initialize(address(addressManager));

        pythOracleAdapter = new PythOracleAdapter(address(pyth));

        makerUtilRatioReporter = new MakerReporter();
        _enableInitialize(address(makerUtilRatioReporter));
        makerUtilRatioReporter.initialize(address(addressManager));

        // Deposit oracle fee
        pythOracleAdapter.depositOracleFee{ value: 1 ether }();

        // copy bytecode to MULTICALLER_WITH_SENDER and initialize the slot 0(reentrancy lock) for it
        vm.etch(MULTICALLER_WITH_SENDER, address(new MulticallerWithSender()).code);
        vm.store(MULTICALLER_WITH_SENDER, bytes32(uint256(0)), bytes32(uint256(1 << 160)));

        vm.mockCall(
            address(pyth),
            abi.encodeWithSelector(AbstractPyth.priceFeedExists.selector, priceFeedId),
            abi.encode(true)
        );

        addressManager.setAddress(VAULT, address(vault));
        addressManager.setAddress(CLEARING_HOUSE, address(clearingHouse));
        addressManager.setAddress(BORROWING_FEE, address(borrowingFee));
        addressManager.setAddress(FUNDING_FEE, address(fundingFee));
        addressManager.setAddress(PYTH_ORACLE_ADAPTER, address(pythOracleAdapter));
        addressManager.setAddress(MAKER_REPORTER, address(makerUtilRatioReporter));
        addressManager.setAddress(CONFIG, address(config));
        addressManager.setAddress(SYSTEM_STATUS, address(systemStatus));
    }

    // function test_PrintMarketSlotIds() public {
    //     // Vault._statMap starts from slot 201 (find slot number in .openzeppelin/xxx.json)
    //     for (uint i = 0; i < 101; i++) {
    //         bytes32 slot = keccak256(abi.encode(0 + i, uint(201)));
    //         console.log(uint256(slot));
    //     }
    // }

    function test_excludeFromCoverageReport() public virtual override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function _setCollateralTokenAsDeflationaryToken() internal {
        vault = new Vault();
        _enableInitialize(address(vault));
        vault.initialize(address(addressManager), address(deflationaryCollateralToken));
        addressManager.setAddress(VAULT, address(vault));
    }

    function _setCollateralTokenAsCustomDecimalsToken(uint8 decimal) internal {
        vault = new Vault();
        _enableInitialize(address(vault));
        collateralToken = ERC20(new TestCustomDecimalsToken("USDC", "USDC", decimal));
        vm.label(address(collateralToken), collateralToken.symbol());
        vault.initialize(address(addressManager), address(collateralToken));
        addressManager.setAddress(VAULT, address(vault));
    }

    // ex: 1234.56 => price: 123456, expo = -2
    function _mockPythPrice(int64 price, int32 expo) internal {
        PythStructs.Price memory basePythPrice = PythStructs.Price(price, 0, expo, block.timestamp);

        vm.mockCall(
            address(pyth),
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId),
            abi.encode(basePythPrice)
        );
    }

    function _mockPythPrice(int64 price, int32 expo, uint256 timestamp) internal {
        PythStructs.Price memory basePythPrice = PythStructs.Price(price, 0, expo, timestamp);

        vm.mockCall(
            address(pyth),
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId),
            abi.encode(basePythPrice)
        );
    }

    // deposit to funding account and transfer to market account
    function _deposit(uint256 _marketId, address trader, uint256 amount) internal {
        deal(address(collateralToken), trader, amount, true);
        vm.startPrank(trader);
        // only approve when needed to prevent disturbing asserting on the next clearingHouse.deposit call
        if (collateralToken.allowance(trader, address(vault)) < amount) {
            collateralToken.approve(address(vault), type(uint256).max);
        }

        // use multicall so that we can have vm.expecttraderabove the _deposit() call
        address[] memory targets = new address[](2);
        targets[0] = address(vault);
        targets[1] = address(vault);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(vault.deposit.selector, trader, amount);
        data[1] = abi.encodeWithSignature("transferFundToMargin(uint256,uint256)", _marketId, amount);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        multicallerWithSender.aggregateWithSender(targets, data, values);
        vm.stopPrank();
    }

    // deposit to funding account
    function _deposit(address trader, uint256 amount) internal {
        deal(address(collateralToken), trader, amount, true);
        vm.startPrank(trader);
        // only approve when needed to prevent disturbing asserting on the next clearingHouse.deposit call
        if (collateralToken.allowance(trader, address(vault)) < amount) {
            collateralToken.approve(address(vault), type(uint256).max);
        }
        vault.deposit(trader, amount);
        vm.stopPrank();
    }

    function _newMarketWithTestMaker(uint256 marketId_) internal returns (TestMaker maker) {
        maker = new TestMaker(vault);
        _newMarket(marketId_);
        config.registerMaker(marketId_, address(maker));
        return maker;
    }

    function _newMarket(uint256 marketId_) internal {
        if (config.getPriceFeedId(marketId_) == 0x0) {
            config.createMarket(marketId_, priceFeedId);
        }
    }

    function _deployPythOracleAdaptorInFork() internal {
        // use Optimism pyth contract address
        pythOracleAdapter = new PythOracleAdapter(0xff1a0f4744e8582DF1aE09D5611b887B6a12925C);
        // Deposit oracle fee
        pythOracleAdapter.depositOracleFee{ value: 1 ether }();
        addressManager.setAddress(PYTH_ORACLE_ADAPTER, address(pythOracleAdapter));
    }

    function _trade(address trader_, address maker_, int256 size, uint256 priceInEther) internal {
        _tradeWithRelayFee(marketId, trader_, maker_, size, priceInEther, makeAddr("relayer"), 0, 0);
    }

    function _tradeWithRelayFee(
        uint256 marketId_,
        address trader_,
        address maker_,
        int256 size_,
        uint256 priceInEther, // when priceInEther = 1, it means 1 ether
        address relayer,
        uint256 takerRelayFee,
        uint256 makerRelayFee
    ) internal {
        // workaround when we have hard coded whitelisted auth
        vm.mockCall(
            address(addressManager),
            abi.encodeWithSelector(AddressManager.getAddress.selector, ORDER_GATEWAY),
            abi.encode(relayer)
        );

        if (!clearingHouse.isAuthorized(trader_, relayer)) {
            vm.prank(trader_);
            clearingHouse.setAuthorization(relayer, true);
        }
        if (!clearingHouse.isAuthorized(maker_, relayer)) {
            vm.prank(maker_);
            clearingHouse.setAuthorization(relayer, true);
        }

        bytes memory makerData;
        if (!config.isWhitelistedMaker(marketId, maker_)) {
            makerData = abi.encode(IClearingHouse.MakerOrder({ amount: (size_.abs() * priceInEther) }));
        }

        vm.prank(relayer);
        clearingHouse.openPositionFor(
            IClearingHouse.OpenPositionForParams({
                marketId: marketId_,
                maker: maker_,
                isBaseToQuote: size_ < 0, // b2q:q2b
                isExactInput: size_ < 0, // (b)2q:q2(b)
                amount: size_.abs(),
                oppositeAmountBound: size_ < 0 ? 0 : type(uint256).max,
                deadline: block.timestamp,
                makerData: makerData,
                taker: trader_,
                takerRelayFee: takerRelayFee,
                makerRelayFee: makerRelayFee
            })
        );
    }

    function _openPosition(uint256 marketId_, address maker_, int256 size_) internal {
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId_,
                maker: maker_,
                isBaseToQuote: size_ < 0, // b2q:q2b
                isExactInput: size_ < 0, // (b)2q:q2(b)
                amount: size_.abs(),
                oppositeAmountBound: size_ < 0 ? 0 : type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );
    }

    function _openPositionFor(
        uint256 marketId_,
        address trader_,
        address maker_,
        int256 size_,
        uint256 priceInEther, // when priceInEther = 1, it means 1 ether
        address relayer,
        uint256 takerRelayFee,
        uint256 makerRelayFee
    ) internal {
        vm.prank(relayer);
        clearingHouse.openPositionFor(
            IClearingHouse.OpenPositionForParams({
                marketId: marketId_,
                maker: maker_,
                isBaseToQuote: size_ < 0, // b2q:q2b
                isExactInput: size_ < 0, // (b)2q:q2(b)
                amount: uint256(size_),
                oppositeAmountBound: size_ < 0 ? 0 : type(uint256).max,
                deadline: block.timestamp,
                makerData: abi.encode(IClearingHouse.MakerOrder({ amount: (uint256(size_) * priceInEther) })),
                taker: trader_,
                takerRelayFee: takerRelayFee,
                makerRelayFee: makerRelayFee
            })
        );
    }

    function _getPosition(uint256 _marketId, address trader) internal view returns (PositionProfile memory) {
        return
            PositionProfile({
                margin: vault.getMargin(_marketId, trader),
                unsettledPnl: vault.getUnsettledPnl(_marketId, trader),
                positionSize: vault.getPositionSize(_marketId, trader),
                openNotional: vault.getOpenNotional(_marketId, trader)
            });
    }

    function _getMarginProfile(
        uint256 marketId_,
        address trader_,
        uint256 price_
    ) internal view returns (LegacyMarginProfile memory) {
        return
            LegacyMarginProfile({
                positionSize: vault.getPositionSize(marketId_, trader_),
                openNotional: vault.getOpenNotional(marketId_, trader_),
                accountValue: vault.getAccountValue(marketId_, trader_, price_),
                unrealizedPnl: vault.getUnrealizedPnl(marketId_, trader_, price_),
                freeCollateral: vault.getFreeCollateral(marketId_, trader_, price_),
                freeCollateralForOpen: vault.getFreeCollateralForTrade(
                    marketId_,
                    trader_,
                    price_,
                    MarginRequirementType.INITIAL
                ),
                freeCollateralForReduce: vault.getFreeCollateralForTrade(
                    marketId_,
                    trader_,
                    price_,
                    MarginRequirementType.MAINTENANCE
                ),
                marginRatio: vault.getMarginRatio(marketId_, trader_, price_)
            });
    }
}
