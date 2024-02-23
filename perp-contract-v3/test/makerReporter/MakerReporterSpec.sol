// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../MockSetup.sol";
import "../../src/makerReporter/MakerReporter.sol";

contract MakerReporterSpec is MockSetup {
    MakerReporter public reporter;
    address public mockMaker = makeAddr("maker");
    uint256 constant FIFTY_PERCENT = 5e17;

    function setUp() public virtual override {
        super.setUp();

        reporter = new MakerReporter();
        _enableInitialize(address(reporter));
        reporter.initialize(mockAddressManager);

        // given ETH = $100, maker has 200 margin, open 1 ETH long
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getMargin.selector, marketId, mockMaker),
            abi.encode(200 ether)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, mockMaker),
            abi.encode(-100 ether)
        );
        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.getPrice.selector),
            abi.encode(100 ether, block.timestamp)
        );
    }

    // TODO: open this when getUtilRatioFactor using IMaker.getUtilRatio
    //    function test_GetMakerUtilRatio_HigherThanMax() public {
    //        // given maker report 100% util ratio, but from margin's perspective it only used 50%
    //        vm.mockCall(mockMaker, abi.encodeWithSelector(IMaker.getUtilRatio.selector), abi.encode(0, 1e18));
    //        (, uint256 shortUtilRatio) = reporter.getUtilRatioFactor(marketId, mockMaker);
    //        assertEq(shortUtilRatio, FIFTY_PERCENT * 100 ether);
    //    }
    //
    //    function test_GetMakerUtilRatio_LowerThanMax() public {
    //        // given maker report 10% util ratio, it's acceptable to let maker report lower
    //        vm.mockCall(mockMaker, abi.encodeWithSelector(IMaker.getUtilRatio.selector), abi.encode(0, 1e17));
    //        (, uint256 shortUtilRatio) = reporter.getUtilRatioFactor(marketId, mockMaker);
    //        assertEq(shortUtilRatio, 1e17 * 100 ether);
    //    }
}
