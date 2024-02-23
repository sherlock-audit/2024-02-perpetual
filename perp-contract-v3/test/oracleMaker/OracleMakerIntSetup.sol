// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../clearingHouse/ClearingHouseIntSetup.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { Vault } from "../../src/vault/Vault.sol";

contract OracleMakerIntSetup is ClearingHouseIntSetup {
    OracleMaker public maker;
    bytes public validPythUpdateDataItem = hex"1234";
    bytes public invalidPythUpdateDataItem = hex"5678";
    string public invalidPythUpdateDataRevertMessage = "TODO: revert message";
    uint256 public oracleFee = 1; // 1 wei

    function setUp() public virtual override {
        ClearingHouseIntSetup.setUp();

        bytes[] memory pythUpdateData = new bytes[](1);

        // Mock Pyth Oracle update with valid data
        pythUpdateData[0] = validPythUpdateDataItem;
        vm.mockCall(
            address(pyth),
            oracleFee,
            abi.encodeWithSelector(IPyth.updatePriceFeeds.selector, pythUpdateData),
            abi.encode(0x0)
        );

        // Mock Pyth Oracle update with invalid data
        pythUpdateData[0] = invalidPythUpdateDataItem;
        vm.mockCallRevert(
            address(pyth),
            oracleFee,
            abi.encodeWithSelector(IPyth.updatePriceFeeds.selector, pythUpdateData),
            abi.encode(invalidPythUpdateDataRevertMessage)
        );

        // Mock Pyth Oracle get update fee
        vm.mockCall(address(pyth), abi.encodeWithSelector(IPyth.getUpdateFee.selector), abi.encode(oracleFee));

        maker = new OracleMaker();
        vm.label(address(maker), "Maker");

        _enableInitialize(address(maker));
        _newMarketWithTestMaker(marketId);
        maker.initialize(marketId, "OM", "OM", address(addressManager), priceFeedId, 1e18);
        config.registerMaker(marketId, address(maker));
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
