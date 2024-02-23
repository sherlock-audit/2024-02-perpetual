// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./VaultSpecSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../helper/TestDeflationaryToken.sol";
import "../../src/vault/FundModelUpgradeable.sol";

contract Deposit is VaultSpecSetup, IFundModelEvent {
    address public taker = makeAddr("taker");

    function setUp() public virtual override {
        super.setUp();

        // prepare collateral
        deal(collateralToken, taker, type(uint256).max);
        vm.prank(taker);
        IERC20(collateralToken).approve(address(vault), type(uint256).max);
    }

    function test_Deposit() public {
        vm.startPrank(taker);
        vm.expectEmit(true, true, true, true, address(vault));
        emit FundChanged(taker, 1);
        vault.deposit(taker, 1);
    }

    function test_RevertIf_ZeroAmount() public {
        vm.startPrank(taker);
        vm.expectRevert(LibError.ZeroAmount.selector);
        vault.deposit(taker, 0);
    }

    function test_RevertIf_MismatchedTransferAmount() public {
        // given collateral is a deflationary token
        TestDeflationaryToken deflationaryToken = new TestDeflationaryToken("DF-USDC", "DF-USDC");
        vault = new Vault();
        _enableInitialize(address(vault));
        vault.initialize(mockAddressManager, address(deflationaryToken));
        deal(address(deflationaryToken), taker, 10 ether);

        // expect it will revert when deposit due to mismatched amount error
        vm.startPrank(taker);
        deflationaryToken.approve(address(vault), 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.MismatchedTransferAmount.selector,
                10 ether - deflationaryToken.fee(),
                10 ether
            )
        );
        vault.deposit(taker, 10 ether);
        vm.stopPrank();
    }

    function test_RevertIf_DepositCapExceeded() public {
        // set depositCap to 1 USDT
        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.getDepositCap.selector), abi.encode(1e6));

        vm.startPrank(taker);

        // deposit 1 USDT should pass
        vault.deposit(taker, 1e6);

        // deposit 1 more USDT should revert
        vm.expectRevert(abi.encodeWithSelector(LibError.DepositCapExceeded.selector));
        vault.deposit(taker, 1e6);
    }
}
