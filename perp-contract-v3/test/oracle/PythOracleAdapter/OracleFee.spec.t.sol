// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { BaseTest } from "../../BaseTest.sol";
import { IPythOracleAdapter } from "../../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { PythOracleAdapter } from "../../../src/oracle/pythOracleAdapter/PythOracleAdapter.sol";
import { LibError } from "../../../src/common/LibError.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PythOracleAdapterWithReceiveOracleFee is BaseTest {
    address public alice = makeAddr("Alice");
    PythOracleAdapter public pythOracleAdapter;

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    address pyth = makeAddr("pyth");

    function setUp() public {
        pythOracleAdapter = new PythOracleAdapter(pyth);
    }

    function test_deposit_And_withdrawOracleFee_Normal() public {
        uint256 depositAmount = 1 ether;

        vm.expectEmit(true, true, true, true, address(pythOracleAdapter));
        emit IPythOracleAdapter.OracleFeeDeposited(address(this), depositAmount);
        pythOracleAdapter.depositOracleFee{ value: depositAmount }();
        assertEq(address(pythOracleAdapter).balance, depositAmount);

        vm.expectEmit(true, true, true, true, address(pythOracleAdapter));
        emit IPythOracleAdapter.OracleFeeWithdrawn(address(this), depositAmount);
        pythOracleAdapter.withdrawOracleFee();
        assertEq(address(pythOracleAdapter).balance, 0);
    }

    function test_withdrawOracleFee_RevertIf_notOwner() public {
        uint256 depositAmount = 1 ether;

        pythOracleAdapter.depositOracleFee{ value: depositAmount }();
        assertEq(address(pythOracleAdapter).balance, depositAmount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        pythOracleAdapter.withdrawOracleFee();
    }
}

contract PythOracleAdapterWithoutReceiveOracleFee is BaseTest {
    PythOracleAdapter public pythOracleAdapter;
    address pyth = makeAddr("pyth");

    function setUp() public {
        pythOracleAdapter = new PythOracleAdapter(pyth);
    }

    function test_withdrawOracleFee_RevertIf_OwnerCanNotReceiveEther() public {
        uint256 depositAmount = 1 ether;
        pythOracleAdapter.depositOracleFee{ value: depositAmount }();

        vm.expectRevert(abi.encodeWithSelector(LibError.WithdrawOracleFeeFailed.selector, depositAmount));
        pythOracleAdapter.withdrawOracleFee();
    }
}
