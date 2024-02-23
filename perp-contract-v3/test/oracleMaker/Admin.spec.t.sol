// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { LibError } from "../../src/common/LibError.sol";
import { OracleMakerSpecSetup } from "./OracleMakerSpecSetup.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract OracleMakerAdminSpec is OracleMakerSpecSetup {
    OracleMaker public maker;
    address public someone = makeAddr("SOME-ONE");
    bytes32 newPriceFeedId = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

    function setUp() public virtual override {
        OracleMakerSpecSetup.setUp();

        maker = _create_OracleMaker(); // _clearingHouse currently not used
    }

    function test_setPriceFeedId_Normal() public {
        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.priceFeedExists.selector, newPriceFeedId),
            abi.encode(true)
        );

        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.PriceFeedIdSet(newPriceFeedId, priceFeedId);
        maker.setPriceFeedId(newPriceFeedId);
    }

    function test_setMinMarginRatio_Normal() public {
        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.MinMarginRatioSet(0.1 ether, 1 ether);
        maker.setMinMarginRatio(0.1 ether);
    }

    function test_setMaxSpreadRatio_Normal() public {
        // set to 1 (100%)
        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.MaxSpreadRatioSet(1 ether, 0 ether);
        maker.setMaxSpreadRatio(1 ether);
        assertEq(maker.maxSpreadRatio(), 1 ether);

        // set to 0 to disable spread
        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.MaxSpreadRatioSet(0 ether, 1 ether);
        maker.setMaxSpreadRatio(0);
        assertEq(maker.maxSpreadRatio(), 0);
    }

    function test_setPriceFeedId_RevertIf_non_admin() public {
        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.priceFeedExists.selector, newPriceFeedId),
            abi.encode(true)
        );

        vm.startPrank(someone);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, someone));
        maker.setPriceFeedId(newPriceFeedId);
        vm.stopPrank();
    }

    function test_setPriceFeedId_RevertIf_invalid_priceFeedId() public {
        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.priceFeedExists.selector, newPriceFeedId),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(LibError.IllegalPriceFeed.selector, newPriceFeedId));
        maker.setPriceFeedId(newPriceFeedId);
    }

    function test_setMinMarginRatio_RevertIf_non_admin() public {
        vm.startPrank(someone);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, someone));
        maker.setMinMarginRatio(0.1 ether);
        vm.stopPrank();
    }

    function test_setMaxSpreadRatio_RevertIf_non_admin() public {
        vm.startPrank(someone);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, someone));
        maker.setMaxSpreadRatio(0.1 ether);
        vm.stopPrank();
    }

    function test_setMaxSpreadRatio_RevertIf_InvalidRatio() public {
        uint256 invalidRatio = 2e18;
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidRatio.selector, invalidRatio));
        maker.setMaxSpreadRatio(invalidRatio);
    }
}
