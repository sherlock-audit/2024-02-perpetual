// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../BaseTest.sol";
import { TestOracleMaker } from "../helper/TestOracleMaker.sol";
import { AddressManager } from "../../src/addressManager/AddressManager.sol";
import { IMarginProfile, MarginRequirementType } from "../../src/vault/IMarginProfile.sol";
import { IVault } from "../../src/vault/IVault.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { LibError } from "../../src/common/LibError.sol";

contract GetBasePriceWithSpreadSpecTest is BaseTest {
    TestOracleMaker public maker;

    address public addressManager = makeAddr("AddressManager");
    address public clearingHouse = makeAddr("ClearingHouse");
    address public vault = makeAddr("Vault");
    address public pythOracleAdapter = makeAddr("PythOracleAdapter");

    uint256 public marketId = 0;
    bytes32 public priceFeedId = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;

    uint256 public pythOraclePrice = 1000 ether;

    function setUp() public virtual {
        vm.mockCall(
            addressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, CLEARING_HOUSE),
            abi.encode(clearingHouse)
        );
        vm.mockCall(
            addressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, VAULT),
            abi.encode(vault)
        );
        vm.mockCall(
            addressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, PYTH_ORACLE_ADAPTER),
            abi.encode(pythOracleAdapter)
        );
        vm.mockCall(
            pythOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.priceFeedExists.selector, priceFeedId),
            abi.encode(true)
        );

        maker = new TestOracleMaker();
        _enableInitialize(address(maker));
        maker.initialize(marketId, "OM", "OM", addressManager, priceFeedId, 1e18);
        maker.setMinMarginRatio(1 ether);
        maker.setMaxSpreadRatio(0.1 ether);
    }

    function test_taker_long_when_no_maker_position() public {
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 100 ether,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        uint256 basePriceWithSpread = maker.getBasePriceWithSpread(pythOraclePrice, false);
        assertEq(basePriceWithSpread, pythOraclePrice);
        assertEq(maker.getPositionRate(pythOraclePrice), 0);
    }

    function test_taker_long_when_maker_has_long_position() public {
        // taker long == maker short
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: 0.1 ether,
                openNotional: -100 ether,
                accountValue: 100 ether,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        uint256 basePriceWithSpread = maker.getBasePriceWithSpread(pythOraclePrice, false);
        // no spread
        assertEq(basePriceWithSpread, pythOraclePrice);
        assertEq(maker.getPositionRate(pythOraclePrice), 1 ether);
    }

    function test_taker_long_when_maker_has_short_position() public {
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: -0.1 ether,
                openNotional: 100 ether,
                accountValue: 100 ether,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        uint256 basePriceWithSpread = maker.getBasePriceWithSpread(pythOraclePrice, false);
        // basePriceWithSpread = basePrice * (1 - -10%)
        assertEq(basePriceWithSpread, 1100 ether);
        assertEq(maker.getPositionRate(pythOraclePrice), -1 ether);
    }

    function test_taker_short_when_maker_has_long_position() public {
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: 0.05 ether,
                openNotional: -50 ether,
                accountValue: 100 ether,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        uint256 basePriceWithSpread = maker.getBasePriceWithSpread(pythOraclePrice, true);
        // basePriceWithSpread = basePrice * (1 - 5%)
        assertEq(basePriceWithSpread, 950 ether);
        assertEq(maker.getPositionRate(pythOraclePrice), 0.5 ether);
    }

    function test_position_rate_capped_by_1() public {
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: 0.05 ether,
                openNotional: -50 ether,
                accountValue: 1 ether,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        // if uncapped, position rate = 50 / 1
        assertEq(maker.getPositionRate(pythOraclePrice), 1 ether);
    }

    function test_position_rate_capped_by_neg_1() public {
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: -0.05 ether,
                openNotional: 50 ether,
                accountValue: 1 ether,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        // if uncapped, position rate = -50 / 1
        assertEq(maker.getPositionRate(pythOraclePrice), -1 ether);
    }

    function test_RevertIf_maker_margin_is_negative() public {
        withMarginProfile(
            LegacyMarginProfile({
                positionSize: 0,
                openNotional: 0,
                accountValue: 0,
                unrealizedPnl: 0,
                freeCollateralForOpen: 0,
                freeCollateralForReduce: 123 ether, // TODO: WIP
                freeCollateral: 0,
                marginRatio: 0
            })
        );
        vm.expectRevert(abi.encodeWithSelector(LibError.NegativeOrZeroMargin.selector));
        maker.getBasePriceWithSpread(pythOraclePrice, true);
    }

    function withMarginProfile(LegacyMarginProfile memory p) public {
        vm.mockCall(vault, abi.encodeWithSelector(IMarginProfile.getPositionSize.selector), abi.encode(p.positionSize));
        vm.mockCall(vault, abi.encodeWithSelector(IMarginProfile.getOpenNotional.selector), abi.encode(p.openNotional));
        vm.mockCall(vault, abi.encodeWithSelector(IMarginProfile.getAccountValue.selector), abi.encode(p.accountValue));
        vm.mockCall(
            vault,
            abi.encodeWithSelector(IMarginProfile.getUnrealizedPnl.selector),
            abi.encode(p.unrealizedPnl)
        );
        vm.mockCall(
            vault,
            abi.encodeWithSelector(
                IMarginProfile.getFreeCollateralForTrade.selector,
                marketId,
                address(maker),
                pythOraclePrice,
                MarginRequirementType.INITIAL
            ),
            abi.encode(p.freeCollateralForOpen)
        );
        vm.mockCall(
            vault,
            abi.encodeWithSelector(
                IMarginProfile.getFreeCollateralForTrade.selector,
                marketId,
                address(maker),
                pythOraclePrice,
                MarginRequirementType.MAINTENANCE
            ),
            abi.encode(p.freeCollateralForReduce)
        );
        vm.mockCall(vault, abi.encodeWithSelector(IMarginProfile.getMarginRatio.selector), abi.encode(p.marginRatio));
    }
}
