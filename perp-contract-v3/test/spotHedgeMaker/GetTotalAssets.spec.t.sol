// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { SpotHedgeBaseMakerSpecSetup } from "./SpotHedgeBaseMakerSpecSetup.sol";
import { IMarginProfile } from "../../src/vault/IMarginProfile.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { LibFormatter } from "../../src/common/LibFormatter.sol";

contract GetTotalAssetsTest is SpotHedgeBaseMakerSpecSetup {
    using LibFormatter for int256;

    SpotHedgeBaseMaker public maker;
    address public lp = makeAddr("LP");

    function setUp() public virtual override {
        SpotHedgeBaseMakerSpecSetup.setUp();

        maker = _create_Maker();
    }

    function testFuzz_getTotalAssets_Normal(int256 accountValue, uint256 baseTokenBalance, uint256 price) public {
        vm.assume(accountValue > -1000000e18 && accountValue < 1000000e18);
        vm.assume(baseTokenBalance < 1000e18);
        vm.assume(price > 0.000001e18 && price < 10000e18);

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

        deal(address(baseToken), address(maker), baseTokenBalance);

        // Assume baseToken.decimals = 9
        assertEq(
            maker.getTotalAssets(price),
            ((accountValue * 1e18) / int256(price) + int256(baseTokenBalance).formatDecimals(9, 18)).formatDecimals(
                18,
                9
            ),
            "unexpected totalAsset"
        );
    }
}
