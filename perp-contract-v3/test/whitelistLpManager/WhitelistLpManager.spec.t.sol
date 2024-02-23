// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { WhitelistLpManager, IWhitelistLpManager } from "../../src/maker/WhitelistLpManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract WhitelistLpManagerSpec is Test {
    WhitelistLpManager public whitelistLpManager;

    function setUp() public {
        whitelistLpManager = new WhitelistLpManager();
    }

    function test_setWhitelistLp() public {
        vm.expectEmit(true, true, true, true);
        emit IWhitelistLpManager.WhitelistLpSet(address(0x1), true, false);

        whitelistLpManager.setWhitelistLp(address(0x1), true);
        assertEq(whitelistLpManager.isLpWhitelisted(address(0x1)), true);
    }

    function test_RevertIf_setWhitelistLpNotOwner() public {
        address notOwner = makeAddr("notOwner");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));

        vm.prank(notOwner);
        whitelistLpManager.setWhitelistLp(address(0x1), true);
    }
}
