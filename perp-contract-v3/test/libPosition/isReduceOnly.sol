// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { LibPosition } from "../../src/vault/LibPosition.sol";

contract IsReduceOnly is Test {
    function test_IncreaseLong() public {
        assertEq(LibPosition.isReduceOnly(5, 10), false);
    }

    function test_ReduceLong() public {
        assertEq(LibPosition.isReduceOnly(10, 5), true);
    }

    function test_ReverseLong() public {
        assertEq(LibPosition.isReduceOnly(10, -10), false);
    }

    function test_OpenLong() public {
        assertEq(LibPosition.isReduceOnly(0, 10), false);
    }

    function test_CloseLong() public {
        assertEq(LibPosition.isReduceOnly(10, 0), true);
    }

    function test_IncreaseShort() public {
        assertEq(LibPosition.isReduceOnly(-5, -10), false);
    }

    function test_ReduceShort() public {
        assertEq(LibPosition.isReduceOnly(-10, -5), true);
    }

    function test_ReverseShort() public {
        assertEq(LibPosition.isReduceOnly(-10, 10), false);
    }

    function test_OpenShort() public {
        assertEq(LibPosition.isReduceOnly(0, -10), false);
    }

    function test_CloseShort() public {
        assertEq(LibPosition.isReduceOnly(-10, 0), true);
    }

    function test_BothZero() public {
        assertEq(LibPosition.isReduceOnly(0, 0), false);
    }
}
