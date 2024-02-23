// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { LibError } from "../../src/common/LibError.sol";
import { OracleMakerSpecSetup } from "./OracleMakerSpecSetup.sol";

contract OracleMakerDepositSpec is OracleMakerSpecSetup {
    OracleMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        OracleMakerSpecSetup.setUp();

        maker = _create_OracleMaker(); // _clearingHouse currently not used

        _mockPythPrice(100, 0);
    }

    function testFuzz_deposit_Normal(uint256 amount) public {
        // TODO: So far we ignore round-down issues for dust deposits. Will address it with decimal offets.
        vm.assume(amount > 1e6);

        deal(collateralToken, lp, amount, true);

        vm.mockCall(
            address(mockVault),
            abi.encodeWithSelector(Vault.deposit.selector, address(maker), amount),
            abi.encode()
        );
        vm.mockCall(
            address(mockClearingHouse),
            abi.encodeWithSelector(bytes4(keccak256("transferFundToMargin(uint256,uint256)")), marketId, amount),
            abi.encode()
        );

        vm.startPrank(lp);
        IERC20(collateralToken).approve(address(maker), amount);

        vm.expectEmit(true, true, true, true, address(maker));
        emit OracleMaker.Deposited(lp, amount, amount); // shares == amount Since this is the first deposit.
        uint256 shares = maker.deposit(amount);

        assertEq(shares, amount); // shares == amount Since this is the first deposit.
        assertEq(maker.balanceOf(lp), amount);
        assertEq(IERC20(collateralToken).balanceOf(lp), 0);
        vm.stopPrank();
    }

    function test_deposit_RevertIf_amount_is_zero() public {
        vm.startPrank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAmount.selector));
        maker.deposit(0);
        vm.stopPrank();
    }

    function testFuzz_deposit_RevertIf_collateralToken_is_deflationaryToken(uint256 amount) public {
        uint256 deflationaryTokenTransferFee = deflationaryCollateralToken.fee();
        vm.assume(amount > deflationaryTokenTransferFee);

        deal(address(deflationaryCollateralToken), lp, amount, true);

        vm.startPrank(lp);
        deflationaryCollateralToken.approve(address(maker), amount);

        vm.mockCall(
            address(mockVault),
            abi.encodeWithSelector(Vault.getCollateralToken.selector),
            abi.encode(address(deflationaryCollateralToken))
        );

        vm.expectRevert(
            abi.encodeWithSelector(LibError.WrongTransferAmount.selector, amount - deflationaryTokenTransferFee, amount)
        );
        maker.deposit(amount);
        vm.stopPrank();
    }
}
