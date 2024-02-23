// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../MockSetup.sol";
import "./FundingFeeHarness.sol";
import { FundingFee } from "../../src/fundingFee/FundingFee.sol";
import { FundingConfig } from "../../src/config/FundingConfig.sol";
import { TestMaker } from "../helper/TestMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { LibError } from "../../src/common/LibError.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract FundingFeeSpec is MockSetup, ERC7201Location {
    FundingFeeHarness fundingFee;
    TestMaker basePool;

    address public trader = makeAddr("trader");
    address public trader2 = makeAddr("trader2");

    function setUp() public override {
        MockSetup.setUp();

        basePool = new TestMaker(Vault(mockVault));
        basePool.setMinMarginRatio(0.5e18);

        fundingFee = new FundingFeeHarness();
        _enableInitialize(address(fundingFee));
        fundingFee.initialize(mockAddressManager);

        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.getFundingConfig.selector),
            abi.encode(
                FundingConfig({ fundingFactor: 0.005e18, fundingExponentFactor: 1.3e18, basePool: address(basePool) })
            )
        );
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(fundingFee.exposed_FUNDING_FEE_STORAGE_LOCATION(), getLocation("perp.storage.fundingFee"));
    }

    function test_getCurrentFundingRate_MakerHasNoPosition() public {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(0)
        );

        assertEq(fundingFee.getCurrentFundingRate(marketId), 0);
    }

    function test_getCurrentFundingRate_NoBasePool() public {
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.getFundingConfig.selector),
            abi.encode(FundingConfig({ fundingFactor: 0.005e18, fundingExponentFactor: 1.3e18, basePool: address(0) }))
        );

        assertEq(fundingFee.getCurrentFundingRate(marketId), 0);
    }

    function test_getCurrentFundingRate_ZeroFundingFactor() public {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(1000 ether)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getSettledMargin.selector, marketId, basePool),
            abi.encode(10000 ether)
        );
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.getFundingConfig.selector),
            abi.encode(FundingConfig({ fundingFactor: 0, fundingExponentFactor: 0, basePool: address(basePool) }))
        );

        assertEq(fundingFee.getCurrentFundingRate(marketId), 0);
    }

    function test_getCurrentFundingRate_MakerHasShortPosition() public {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(100 ether)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getSettledMargin.selector, marketId, basePool),
            abi.encode(900 ether)
        );

        // rate = (100^1.3 * 0.005) / (900 / 0.5) = -0.0011058533
        assertEq(fundingFee.getCurrentFundingRate(marketId), -0.001105853251537492e18);
    }

    function test_getCurrentFundingRate_MakerHasLongPosition() public {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(-150 ether)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getSettledMargin.selector, marketId, basePool),
            abi.encode(1200 ether)
        );

        // rate = (150^1.3 * 0.005) / (1200 / 0.5) = 0.0014050035
        assertEq(fundingFee.getCurrentFundingRate(marketId), 0.001405003478274974e18);
    }

    function test_updateFundingGrowthIndex_MakerOpenLongThenReverseToShort() public {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(0)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getSettledMargin.selector, marketId, basePool),
            abi.encode(1000 ether)
        );

        fundingFee.exposed_updateFundingGrowthIndex(marketId);

        assertEq(fundingFee.exposed_fundingGrowthLongIndexMap(marketId), 0);
        assertEq(fundingFee.exposed_lastUpdatedTimestampMap(marketId), block.timestamp);

        // maker has long position
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(-150 ether)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getSettledMargin.selector, marketId, basePool),
            abi.encode(1200 ether)
        );

        skip(100);

        // rate = (150^1.3 * 0.005) / (1200 / 0.5) = 0.0014050035
        fundingFee.exposed_updateFundingGrowthIndex(marketId);

        assertEq(fundingFee.exposed_fundingGrowthLongIndexMap(marketId), 0.1405003478274974e18);
        assertEq(fundingFee.exposed_lastUpdatedTimestampMap(marketId), block.timestamp);

        // maker reverse to short position
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, basePool),
            abi.encode(100 ether)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getSettledMargin.selector, marketId, basePool),
            abi.encode(900 ether)
        );

        skip(100);

        // rate = (100^1.3 * 0.005) / (900 / 0.5) = -0.0011058533
        fundingFee.exposed_updateFundingGrowthIndex(marketId);

        //  0.1405003478274974 - 0.1105853251537492 = 0.0299150227
        assertEq(fundingFee.exposed_fundingGrowthLongIndexMap(marketId), 0.029915022673748200e18);
        assertEq(fundingFee.exposed_lastUpdatedTimestampMap(marketId), block.timestamp);
    }

    function test_settleFundingFee_TakerHasNoPosition() public {
        fundingFee.setFundingGrowthLongIndex(marketId, 0.029915022673748200e18);
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader), abi.encode(0));

        int256 fundingFeePayment = 0;

        vm.expectEmit(true, true, true, true, address(fundingFee));
        emit FundingFee.FundingFeeSettled(marketId, trader, fundingFeePayment);
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), fundingFeePayment);
    }

    function test_settleFundingFee_GrowthIndexIncreasedAndTakerHasShortPosition() public {
        fundingFee.setFundingGrowthLongIndex(marketId, 0.029915022673748200e18);

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader),
            abi.encode(100 ether)
        );

        int256 fundingFeePayment = 2.9915022673748200e18;

        vm.expectEmit(true, true, true, true, address(fundingFee));
        emit FundingFee.FundingFeeSettled(marketId, trader, fundingFeePayment);
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), fundingFeePayment);
    }

    function test_settleFundingFee_GrowthIndexIncreasedAndTakerHasLongPosition() public {
        fundingFee.setFundingGrowthLongIndex(marketId, 0.029915022673748200e18);

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader),
            abi.encode(-100 ether)
        );

        int256 fundingFeePayment = -2.9915022673748200e18;

        vm.expectEmit(true, true, true, true, address(fundingFee));
        emit FundingFee.FundingFeeSettled(marketId, trader, fundingFeePayment);
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), fundingFeePayment);
    }

    function test_settleFundingFee_GrowthIndexDecreasedAndTakerHasShortPosition() public {
        fundingFee.setFundingGrowthLongIndex(marketId, -0.029915022673748200e18);

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader),
            abi.encode(100 ether)
        );

        int256 fundingFeePayment = -2.9915022673748200e18;

        vm.expectEmit(true, true, true, true, address(fundingFee));
        emit FundingFee.FundingFeeSettled(marketId, trader, fundingFeePayment);
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), fundingFeePayment);
    }

    function test_settleFundingFee_GrowthIndexDecreasedAndTakerHasLongPosition() public {
        fundingFee.setFundingGrowthLongIndex(marketId, -0.029915022673748200e18);

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader),
            abi.encode(-100 ether)
        );

        int256 fundingFeePayment = 2.9915022673748200e18;

        vm.expectEmit(true, true, true, true, address(fundingFee));
        emit FundingFee.FundingFeeSettled(marketId, trader, fundingFeePayment);
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), fundingFeePayment);
    }

    function test_settleFundingFee() public {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, trader),
            abi.encode(-100 ether)
        );

        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), 0);
        assertEq(fundingFee.exposed_lastFundingGrowthLongIndexMap(marketId, trader), 0);

        fundingFee.setFundingGrowthLongIndex(marketId, 0.029915022673748200e18);

        // (0.029915022673748200e18 - 0) * (-100) = -2.99150226737482
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), -2.99150226737482e18);
        assertEq(fundingFee.exposed_lastFundingGrowthLongIndexMap(marketId, trader), 0.029915022673748200e18);

        // (-0.019915022673748200e18 - 0.029915022673748200e18) * (-100) = 4.98300453
        fundingFee.setFundingGrowthLongIndex(marketId, -0.019915022673748200e18);
        assertEq(fundingFee.exposed_settleFundingFee(marketId, trader), 4.98300453474964e18);
        assertEq(fundingFee.exposed_lastFundingGrowthLongIndexMap(marketId, trader), -0.019915022673748200e18);
    }

    function test_calcFundingFee_RoundUpWhenPayingFundingFee() public {
        int256 openNotional = 100.987651523865748233 ether;
        int256 deltaGrowthIndex = 0.029915022673748233e18;
        assertEq(
            fundingFee.exposed_calcFundingFee(openNotional, deltaGrowthIndex),
            int256(openNotional * deltaGrowthIndex) / 1e18 + 1
        );

        openNotional = -100.987651523865748233 ether;
        deltaGrowthIndex = -0.029915022673748233e18;
        assertEq(
            fundingFee.exposed_calcFundingFee(openNotional, deltaGrowthIndex),
            int256(openNotional * deltaGrowthIndex) / 1e18 + 1
        );
    }

    function test_calcFundingFee_RoundToZeroWhenReceivingFundingFee() public {
        int256 openNotional = -100.987651523865748233 ether;
        int256 deltaGrowthIndex = 0.029915022673748233e18;
        assertEq(
            fundingFee.exposed_calcFundingFee(openNotional, deltaGrowthIndex),
            int256(openNotional * deltaGrowthIndex) / 1e18
        );

        openNotional = 100.987651523865748233 ether;
        deltaGrowthIndex = -0.029915022673748233e18;
        assertEq(
            fundingFee.exposed_calcFundingFee(openNotional, deltaGrowthIndex),
            int256(openNotional * deltaGrowthIndex) / 1e18
        );
    }

    function test_beforeUpdateMargin_RevertIf_NotFromVault() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        fundingFee.beforeUpdateMargin(marketId, trader);
    }

    function test_beforeSettle_RevertIf_NotFromVault() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.Unauthorized.selector));
        fundingFee.beforeSettlePosition(marketId, trader, trader2);
    }
}
