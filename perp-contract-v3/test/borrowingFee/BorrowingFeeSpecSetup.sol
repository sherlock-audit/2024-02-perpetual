// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../MockSetup.sol";
import { IMakerReporter } from "../../src/makerReporter/IMakerReporter.sol";
import { TestBorrowingFee } from "../helper/TestBorrowingFee.sol";

contract BorrowingFeeSpecSetup is MockSetup {
    TestBorrowingFee public borrowingFee;
    address public payer1 = makeAddr("payer1");
    address public payer2 = makeAddr("payer2");
    address public receiver1 = makeAddr("receiver1");
    address public receiver2 = makeAddr("receiver2");

    function setUp() public virtual override {
        super.setUp();

        borrowingFee = new TestBorrowingFee();
        _enableInitialize(address(borrowingFee));
        borrowingFee.initialize(mockAddressManager);

        // mock vault position
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getPositionSize.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getOpenNotional.selector), abi.encode(0));

        // mock whitelisted maker (receiver)
        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.isWhitelistedMaker.selector), abi.encode(false));
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.isWhitelistedMaker.selector, marketId, receiver1),
            abi.encode(true)
        );
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.isWhitelistedMaker.selector, marketId, receiver2),
            abi.encode(true)
        );
        _mockLocalUtilRatioFactor(receiver1, 0, 0);
        _mockLocalUtilRatioFactor(receiver2, 0, 0);

        // mock getMaxBorrowingFeeRate = 100% per seconds
        vm.prank(mockConfig);
        borrowingFee.setMaxBorrowingFeeRate(marketId, 1 ether, 1 ether);
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    //
    // INTERNAL
    //

    function _mockPosition(address taker, int256 size, int256 openNotional) internal {
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getPositionSize.selector, marketId, taker),
            abi.encode(size)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(Vault.getOpenNotional.selector, marketId, taker),
            abi.encode(openNotional)
        );
    }

    function _mockLocalUtilRatioFactor(address receiver, uint256 longFactor, uint256 shortFactor) internal {
        vm.mockCall(
            mockMakerReporter,
            abi.encodeWithSelector(IMakerReporter.getUtilRatioFactor.selector, marketId, receiver),
            abi.encode(longFactor, shortFactor)
        );
    }

    function _beforeSettle(
        address taker,
        address maker,
        int256 takerPositionSize,
        int256 takerOpenNotional
    ) internal returns (int256, int256) {
        vm.prank(mockVault);
        return borrowingFee.beforeSettlePosition(marketId, taker, maker, takerPositionSize, takerOpenNotional);
    }

    function _afterSettle(address maker) internal {
        vm.prank(mockVault);
        borrowingFee.afterSettlePosition(marketId, maker);
    }

    function _settle(
        uint256 marketIdArg,
        address taker,
        address maker,
        int256 posDelta,
        int256 openNotionalDelta
    ) internal {
        _settleWithReceiver(marketIdArg, taker, maker, posDelta, openNotionalDelta, address(0), 0);
    }

    function _settleWithReceiver(
        uint256 marketIdArg,
        address taker,
        address maker,
        int256 posDelta,
        int256 openNotionalDelta,
        address receiver,
        uint256 makerUtilRatio
    ) internal {
        int256 oldTakerSize = Vault(mockVault).getPositionSize(marketIdArg, taker);
        int256 oldTakerOpenNotional = Vault(mockVault).getOpenNotional(marketIdArg, taker);
        int256 oldMakerSize = Vault(mockVault).getPositionSize(marketIdArg, maker);
        int256 oldMakerOpenNotional = Vault(mockVault).getOpenNotional(marketIdArg, maker);

        _beforeSettle(taker, maker, posDelta, openNotionalDelta);

        if (taker == receiver) {
            revert("taker can not be borrowing fee receiver");
        }
        // mock maker util ratio if it's receiver
        if (receiver == maker) {
            if (posDelta > 0) {
                _mockLocalUtilRatioFactor(maker, makerUtilRatio, 0);
            } else {
                _mockLocalUtilRatioFactor(maker, 0, makerUtilRatio);
            }
        } else if (receiver != address(0)) {
            revert("if receiver is not maker, it must be 0");
        }

        _mockPosition(taker, oldTakerSize + posDelta, oldTakerOpenNotional + openNotionalDelta);
        _mockPosition(maker, oldMakerSize - posDelta, oldMakerOpenNotional - openNotionalDelta);
        _afterSettle(maker);
    }

    function _getUtilRatio(uint256 marketId) internal view returns (uint256, uint256) {
        (LibUtilizationGlobal.Info memory longGlobal, LibUtilizationGlobal.Info memory shortGlobal) = borrowingFee
            .getUtilizationGlobal(marketId);
        return (longGlobal.utilRatio, shortGlobal.utilRatio);
    }
}
