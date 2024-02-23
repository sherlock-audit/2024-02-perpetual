// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";

contract OracleMakerConstructor is Test {
    IPyth public pyth = IPyth(makeAddr("pyth"));
    bytes32 public priceFeedId = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;

    function setUp() public {}

    function test_construct_RevertIf_DisableInitialize() public {
        OracleMaker maker = new OracleMaker();

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        maker.initialize(0, "OM", "OM", address(0x0), priceFeedId, 1e18);
    }
}
