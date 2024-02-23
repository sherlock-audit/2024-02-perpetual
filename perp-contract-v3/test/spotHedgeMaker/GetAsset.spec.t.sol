// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { SpotHedgeBaseMakerSpecSetup } from "./SpotHedgeBaseMakerSpecSetup.sol";
import { Vault } from "../../src/vault/Vault.sol";

contract GetAssetTest is SpotHedgeBaseMakerSpecSetup {
    SpotHedgeBaseMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        SpotHedgeBaseMakerSpecSetup.setUp();

        maker = _create_Maker();
    }

    function test_getAsset_Normal() public {
        assertEq(maker.getAsset(), address(baseToken), "asset should be base token");
    }
}
