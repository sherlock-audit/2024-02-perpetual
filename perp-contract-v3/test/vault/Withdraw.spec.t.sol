// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./VaultSpecSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/vault/FundModelUpgradeable.sol";

contract Withdraw is VaultSpecSetup, IFundModelEvent {
    address public taker = makeAddr("taker");

    function test_Withdraw() public {
        // given taker has 100
        deal(collateralToken, taker, 100);
        vm.startPrank(taker);
        IERC20(collateralToken).approve(address(vault), 100);
        vault.deposit(taker, 100);

        // when withdraw, emit
        vm.expectEmit(true, true, true, true, address(vault));
        emit FundChanged(taker, -100);
        vault.withdraw(100);
        vm.stopPrank();
    }

    function test_RevertIf_ZeroAmount() public {
        vm.expectRevert(LibError.ZeroAmount.selector);
        vm.prank(taker);
        vault.withdraw(0);
    }
}
