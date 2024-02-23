// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { OracleMakerSpecSetup } from "./OracleMakerSpecSetup.sol";
import { Vault } from "../../src/vault/Vault.sol";

contract GetAssetTest is OracleMakerSpecSetup {
    OracleMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        OracleMakerSpecSetup.setUp();

        maker = _create_OracleMaker();
    }

    function test_getAsset_Normal() public {
        address collateralToken = makeAddr("CollateralToken");

        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getCollateralToken.selector), abi.encode(collateralToken));

        assertEq(maker.getAsset(), collateralToken, "asset should be vault's collateral token");
    }
}
