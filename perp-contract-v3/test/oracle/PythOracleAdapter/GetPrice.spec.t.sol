// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { BaseTest } from "../../BaseTest.sol";
import { PythOracleAdapter } from "../../../src/oracle/pythOracleAdapter/PythOracleAdapter.sol";
import { IPythOracleAdapter } from "../../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { LibError } from "../../../src/common/LibError.sol";

contract GetPrice is BaseTest {
    PythOracleAdapter public pythOracleAdapter;

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    address pyth = makeAddr("pyth");
    bytes32 public priceFeedId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    function setUp() public {
        pythOracleAdapter = new PythOracleAdapter(pyth);
    }

    function test_Success() public {
        PythStructs.Price memory basePythPrice = PythStructs.Price(10000, 0, -2, 1000);
        vm.mockCall(
            pyth,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId, 60),
            abi.encode(basePythPrice)
        );
        (uint256 price, uint256 timestamp) = pythOracleAdapter.getPrice(priceFeedId);
        assertEq(price, 100e18);
        assertEq(timestamp, 1000);
    }

    function test_RevertIf_IllegalPrice() public {
        PythStructs.Price memory basePythPrice = PythStructs.Price(10000, 0, 6, 1000);
        vm.mockCall(
            pyth,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId, 60),
            abi.encode(basePythPrice)
        );
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.IllegalPrice.selector, basePythPrice));
        pythOracleAdapter.getPrice(priceFeedId);
    }

    function test_RevertIf_GetPriceReverted() public {
        vm.mockCallRevert(
            pyth,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId, 60),
            abi.encode("test")
        );
        vm.expectRevert(abi.encodeWithSelector(LibError.OracleDataRequired.selector, priceFeedId, abi.encode("test")));
        pythOracleAdapter.getPrice(priceFeedId);
    }
}
