// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import "../src/addressResolver/LibAddressResolver.sol";
import "../src/common/LibError.sol";
import { OrderGateway } from "../src/orderGateway/OrderGateway.sol";
import { Position } from "../src/vault/PositionModelStruct.sol";
import { LibUtilization, LibUtilizationGlobal } from "./helper/TestBorrowingFee.sol";

// was using Position struct which has a uint margin but getMargin is int, so wrap into PositionProfile for int margin
struct PositionProfile {
    int256 margin;
    int256 positionSize;
    int256 openNotional;
    int256 unsettledPnl;
}

/// @param freeCollateral Traditional sense of free collateral (for withdrawal)
/// @param freeCollateralForOpen Free collateral specifically for open position
/// It is signed because we rely on negative values to detect invalid open positions:
/// https://github.com/perpetual-protocol/lugia-contract/blob/9cf08693009e6c4331023bafedd4b020f6c4d31a/src/ClearingHouse.sol#L548-L550
/// When negative, it means the amount short for maintaining the imRatio
struct LegacyMarginProfile {
    int256 positionSize;
    int256 openNotional;
    int256 accountValue;
    int256 unrealizedPnl;
    uint256 freeCollateral;
    int256 freeCollateralForOpen; // Margin rules for increasing positions
    int256 freeCollateralForReduce; // Margin rules for reducing or closing positions
    int256 marginRatio;
}

contract BaseTest is Test {
    using FixedPointMathLib for int256;

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function _assertApproxGteAbs(int256 a, int256 b, uint256 maxDelta, string memory err) internal {
        uint256 absA = a.abs();
        uint256 absB = b.abs();
        assert(absA >= absB);
        assertApproxEqAbs(absA, absB, maxDelta, err);
    }

    function _assertApproxGteAbs(int256 a, int256 b, uint256 maxDelta) internal {
        _assertApproxGteAbs(a, b, maxDelta, "");
    }

    function _assertEq(LegacyMarginProfile memory a, LegacyMarginProfile memory b) internal {
        assertEq(a.positionSize, b.positionSize, "position size");
        assertEq(a.openNotional, b.openNotional, "open notional");
        assertEq(a.accountValue, b.accountValue, "account value");
        assertEq(a.unrealizedPnl, b.unrealizedPnl, "unrealized PnL");
        assertEq(a.freeCollateral, b.freeCollateral, "free collateral");
        assertEq(a.freeCollateralForOpen, b.freeCollateralForOpen, "free collateral for open");
        assertEq(a.freeCollateralForReduce, b.freeCollateralForReduce, "free collateral for reduce");
        assertEq(a.marginRatio, b.marginRatio, "margin ratio");
    }

    function _assertEq(PositionProfile memory a, PositionProfile memory b) internal {
        assertEq(a.margin, b.margin, "margin");
        assertEq(a.positionSize, b.positionSize, "position size");
        assertEq(a.openNotional, b.openNotional, "open notional");
        assertEq(a.unsettledPnl, b.unsettledPnl, "unsettled PnL");
    }

    function _assertEq(Position memory a, Position memory b) internal {
        assertEq(a.margin, b.margin, "margin");
        assertEq(a.positionSize, b.positionSize, "position size");
        assertEq(a.openNotional, b.openNotional, "open notional");
        assertEq(a.unsettledPnl, b.unsettledPnl, "unsettled PnL");
    }

    function _assertEq(OrderGateway.DelayedOrder memory a, OrderGateway.DelayedOrder memory b) internal {
        assertEq(uint(a.orderType), uint(b.orderType));
        assertEq(a.sender, b.sender);
        assertEq(a.data, b.data);
        assertEq(a.createdAt, b.createdAt);
        assertEq(a.executableAt, b.executableAt);
    }

    function _enableInitialize(address account) internal {
        // from Initializable.INITIALIZABLE_STORAGE (ERC7201 namespaced storage layout)
        bytes32 _slotInitialized = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(account, _slotInitialized, bytes32(uint256(0)));
    }

    function _assertEq(LibUtilizationGlobal.Info memory a, LibUtilizationGlobal.Info memory b) internal {
        assertEq(a.totalReceiverOpenNotional, b.totalReceiverOpenNotional);
        assertEq(a.totalOpenNotional, b.totalOpenNotional);
        assertEq(a.utilRatio, b.utilRatio);
    }

    function _assertEq(LibUtilization.Info memory a, LibUtilization.Info memory b) internal {
        assertEq(a.payerIncreasedSize, b.payerIncreasedSize);
        assertEq(a.utilRatioFactor, b.utilRatioFactor);
    }
}
