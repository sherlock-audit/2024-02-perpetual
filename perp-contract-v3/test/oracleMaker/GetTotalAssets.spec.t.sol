// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { OracleMakerSpecSetup } from "./OracleMakerSpecSetup.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { IMarginProfile } from "../../src/vault/IMarginProfile.sol";
import { LibFormatter } from "../../src/common/LibFormatter.sol";

contract GetTotalAssetsTest is OracleMakerSpecSetup {
    using LibFormatter for int256;

    OracleMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        OracleMakerSpecSetup.setUp();

        maker = _create_OracleMaker();

        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.getPrice.selector, priceFeedId),
            abi.encode(1 ether, block.timestamp)
        );
    }

    function testFuzz_getTotalAssets_Normal(int256 accountValue) public {
        vm.assume(accountValue > type(int256).min); // Avoid overflow in unreasonable edge cases.

        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IMarginProfile.getAccountValue.selector, marketId, address(maker)),
            abi.encode(accountValue)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IMarginProfile.getFreeCollateralForTrade.selector, marketId, address(maker)),
            abi.encode(
                123 ether // TODO: WIP
            )
        );

        // Assume collateralToken.decimals = 6
        assertEq(
            maker.getTotalAssets(123), // price is no-op
            accountValue.formatDecimals(18, 6),
            "totalAsset should follow accountValue"
        );
    }
}
