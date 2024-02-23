// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { LibError } from "../../src/common/LibError.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { TestDeflationaryToken } from "../helper/TestDeflationaryToken.sol";
import { SpotHedgeBaseMakerSpecSetup } from "./SpotHedgeBaseMakerSpecSetup.sol";

contract SpotHedgeBaseMakerDepositSpec is SpotHedgeBaseMakerSpecSetup {
    SpotHedgeBaseMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        SpotHedgeBaseMakerSpecSetup.setUp();

        maker = _create_Maker();
    }

    function testFuzz_deposit_Normal(uint256 amount) public {
        vm.assume(amount > 0);

        deal(address(baseToken), lp, amount, true);

        vm.startPrank(lp);
        baseToken.approve(address(maker), amount);

        uint256 shares = maker.deposit(amount);

        assertEq(shares, amount);
        assertEq(maker.balanceOf(lp), amount);
        assertEq(baseToken.balanceOf(lp), 0);
        assertEq(baseToken.balanceOf(address(maker)), amount);
        assertEq(maker.baseTokenLiability(), amount);
        vm.stopPrank();
    }

    function test_deposit_RevertIf_amount_is_zero() public {
        vm.startPrank(lp);

        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAmount.selector));
        maker.deposit(0);
        vm.stopPrank();
    }
}

contract SpotHedgeBaseMakerDepositDeflationaryTokenSpec is SpotHedgeBaseMakerSpecSetup {
    SpotHedgeBaseMaker public maker;
    address public lp = makeAddr("LP");
    TestDeflationaryToken public deflationaryBaseToken;

    function setUp() public virtual override {
        SpotHedgeBaseMakerSpecSetup.setUp();

        deflationaryBaseToken = new TestDeflationaryToken("DF-baseToken", "DF-baseToken");

        SpotHedgeBaseMakerSpecSetup.init(address(deflationaryBaseToken));

        maker = _create_Maker();
    }

    function testFuzz_deposit_RevertIf_baseToken_is_deflationaryToken(uint256 amount) public {
        uint256 deflationaryTokenTransferFee = deflationaryBaseToken.fee();
        vm.assume(amount > deflationaryTokenTransferFee);

        deal(address(deflationaryBaseToken), lp, amount, true);

        vm.startPrank(lp);
        deflationaryBaseToken.approve(address(maker), amount);

        vm.expectRevert(
            abi.encodeWithSelector(LibError.WrongTransferAmount.selector, amount - deflationaryTokenTransferFee, amount)
        );
        maker.deposit(amount);
        vm.stopPrank();
    }
}
