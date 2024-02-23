// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "./OracleMakerSpecSetup.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { IMarginProfile, MarginRequirementType } from "../../src/vault/IMarginProfile.sol";

contract OracleMakerFillOrderSpec is OracleMakerSpecSetup {
    OracleMaker public maker;

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    uint256 price = 123.45e18;

    function setUp() public virtual override {
        OracleMakerSpecSetup.setUp();

        // price = 123.45
        _mockPythPrice(12345, -2);
        // Mock Pyth Oracle update with valid data
        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.getPrice.selector, priceFeedId),
            abi.encode(price, block.timestamp)
        );

        maker = _create_OracleMaker(); // _clearingHouse currently not used
    }

    function testFuzz_fillOrder_B2Q_exactInput_Normal_om(uint256 baseAmount) public {
        // Fuzz test and assume there will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        vm.assume(baseAmount < 1e36);

        uint256 expectedOppositeAmount = (baseAmount * price) / 1 ether;

        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.OMOrderFilled(marketId, price, -int256(baseAmount), int256(expectedOppositeAmount));
        _mockAccValue(100 ether);
        _mockFreeCollateralForReduce(123 ether); // TODO: WIP
        vm.prank(mockClearingHouse);
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            true, // isBaseToQuote
            true, // isExactInput
            baseAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedOppositeAmount, 18);
        assertEq(callbackData, new bytes(0));
    }

    function testFuzz_fillOrder_Q2B_exactInput_Normal(uint256 quoteAmount) public {
        // Fuzz test and assume there will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        vm.assume(quoteAmount < 1e36);

        uint256 expectedOppositeAmount = (quoteAmount * 1 ether) / price;

        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.OMOrderFilled(marketId, price, int256(expectedOppositeAmount), -int256(quoteAmount));
        _mockAccValue(100 ether);
        _mockFreeCollateralForReduce(123 ether); // TODO: WIP
        vm.prank(mockClearingHouse);
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            false, // isBaseToQuote
            true, // isExactInput
            quoteAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedOppositeAmount, 18);
        assertEq(callbackData, new bytes(0));
    }

    function testFuzz_fillOrder_B2Q_exactOutput_Normal(uint256 quoteAmount) public {
        // Fuzz test and assume there will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        vm.assume(quoteAmount < 1e36);

        uint256 expectedOppositeAmount = (quoteAmount * 1 ether) / price;

        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.OMOrderFilled(marketId, price, -int256(expectedOppositeAmount), int256(quoteAmount));
        _mockAccValue(100 ether);
        _mockFreeCollateralForReduce(123 ether); // TODO: WIP
        vm.prank(mockClearingHouse);
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            true, // isBaseToQuote
            false, // isExactInput
            quoteAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedOppositeAmount, 18);
        assertEq(callbackData, new bytes(0));
    }

    function testFuzz_fillOrder_Q2B_exactOutput_Normal(uint256 baseAmount) public {
        // Fuzz test and assume there will never be a amount larger than 1e18 (in decimal) (that's a lot!)
        vm.assume(baseAmount < 1e36);

        uint256 expectedOppositeAmount = (baseAmount * price) / 1e18;

        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.OMOrderFilled(marketId, price, int256(baseAmount), -int256(expectedOppositeAmount));
        _mockAccValue(100 ether);
        _mockFreeCollateralForReduce(123 ether); // TODO: WIP
        vm.prank(mockClearingHouse);
        (uint256 oppositeAmount, bytes memory callbackData) = maker.fillOrder(
            false, // isBaseToQuote
            false, // isExactInput
            baseAmount,
            ""
        );

        assertEqDecimal(oppositeAmount, expectedOppositeAmount, 18);
        assertEq(callbackData, new bytes(0));
    }

    //
    // PRIVATE
    //

    function _mockAccValue(uint256 accValue) private {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IMarginProfile.getAccountValue.selector, marketId, address(maker)),
            abi.encode(accValue)
        );
    }

    function _mockFreeCollateralForReduce(uint256 freeCollateralForReduce) private {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(
                IMarginProfile.getFreeCollateralForTrade.selector,
                marketId,
                address(maker),
                price,
                MarginRequirementType.MAINTENANCE
            ),
            abi.encode(freeCollateralForReduce)
        );
    }
}
