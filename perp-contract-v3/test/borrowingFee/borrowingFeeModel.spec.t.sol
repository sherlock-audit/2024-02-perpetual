// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import { BorrowingFeeModel } from "../../src/borrowingFee/BorrowingFeeModel.sol";
import { ERC7201Location } from "../helper/ERC7201Location.sol";

contract BorrowingFeeModelHarness is BorrowingFeeModel {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // No-op
    function _getUtilRatioFactor(uint256 marketId, address receiver) internal view override returns (uint256, uint256) {
        return (0, 0);
    }

    // No-op
    function _getOpenNotional(uint256 marketId, address payer) internal view override returns (int256) {
        return 0;
    }

    function exposed_BORROWING_FEE_MODEL_STORAGE_LOCATION() external view returns (bytes32) {
        return _BORROWING_FEE_MODEL_STORAGE_LOCATION;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}

contract BorrowingFeeModelSpec is BaseTest, ERC7201Location {
    BorrowingFeeModelHarness public borrowingFeeModelHarness;

    function setUp() public {
        borrowingFeeModelHarness = new BorrowingFeeModelHarness();
    }

    // Test against expected storage location so we don't accidentally change it in the source
    function test_storageLocation() public {
        assertEq(
            borrowingFeeModelHarness.exposed_BORROWING_FEE_MODEL_STORAGE_LOCATION(),
            getLocation("perp.storage.borrowingFeeModel")
        );
    }
}
