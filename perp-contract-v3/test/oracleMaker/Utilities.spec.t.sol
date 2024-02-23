// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { BaseTest } from "../BaseTest.sol";
import { PythOracleAdapter } from "../../src/oracle/pythOracleAdapter/PythOracleAdapter.sol";

contract PythOracleAdapterHarness is PythOracleAdapter {
    PythOracleAdapter public maker;

    constructor(address pyth_) PythOracleAdapter(pyth_) {}

    function exposed_convertToUint256(PythStructs.Price memory pythPrice) external pure returns (uint256) {
        return _convertToUint256(pythPrice);
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract OracleMakerUtilities is BaseTest {
    PythOracleAdapterHarness public adapter;
    IPyth public pyth = IPyth(makeAddr("pyth"));
    bytes32 public priceFeedId = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;

    function setUp() public {
        vm.mockCall(
            address(pyth),
            abi.encodeWithSelector(AbstractPyth.priceFeedExists.selector, priceFeedId),
            abi.encode(true)
        );

        adapter = new PythOracleAdapterHarness(address(pyth));
    }

    function testFuzz_convertToUint256_Normal(int64 price, int32 expo) public {
        vm.assume(price >= 0 && expo <= 0 && expo >= -18);

        PythStructs.Price memory pythPrice = PythStructs.Price({ price: price, conf: 0, expo: expo, publishTime: 0 });

        uint256 baseConversion = 10 ** uint256(int256(int32(18) + pythPrice.expo));
        uint256 expected = uint256(int256(pythPrice.price)) * baseConversion;
        assertEqDecimal(adapter.exposed_convertToUint256(pythPrice), expected, 18);
    }

    function test_convertToUint256_RevertIf_NegativePrice() public {
        int64 invalidPrice = int64(-1);
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: invalidPrice,
            conf: 0,
            expo: -18,
            publishTime: 0
        });
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.IllegalPrice.selector, pythPrice));
        adapter.exposed_convertToUint256(pythPrice);
    }

    function test_convertToUint256_RevertIf_PositiveExpo() public {
        int32 invalidExpo = 18;
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: int64(1),
            conf: 0,
            expo: invalidExpo,
            publishTime: 0
        });
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.IllegalPrice.selector, pythPrice));
        adapter.exposed_convertToUint256(pythPrice);
    }

    function test_convertToUint256_RevertIf_OutOfBoundNegativeExpo() public {
        int32 invalidExpo = -19;
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: int64(1),
            conf: 0,
            expo: invalidExpo,
            publishTime: 0
        });
        vm.expectRevert(abi.encodeWithSelector(PythOracleAdapter.IllegalPrice.selector, pythPrice));
        adapter.exposed_convertToUint256(pythPrice);
    }
}
