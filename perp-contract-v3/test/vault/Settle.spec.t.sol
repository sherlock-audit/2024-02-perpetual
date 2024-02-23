// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./VaultSpecSetup.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { Config } from "../../src/config/Config.sol";
import { IMaker } from "../../src/maker/IMaker.sol";
import { IVault } from "../../src/vault/IVault.sol";
import { IBorrowingFee } from "../../src/borrowingFee/IBorrowingFee.sol";

contract Settle is VaultSpecSetup {
    address public taker = makeAddr("taker");
    address public maker = makeAddr("maker");

    function setUp() public override {
        super.setUp();

        vm.mockCall(maker, abi.encodeWithSelector(IMaker.getUtilRatio.selector), abi.encode(0, 0));
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.isWhitelistedMaker.selector, marketId, maker),
            abi.encode(true)
        );
    }

    function test_settle() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(maker),
            address(maker),
            -10,
            10,
            0,
            PositionChangedReason.Trade
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(maker),
            10,
            -10,
            0,
            PositionChangedReason.Liquidate
        );

        // when settle between taker & maker
        vm.prank(mockClearingHouse);
        vault.settlePosition(
            IVault.SettlePositionParams(marketId, taker, maker, 10, -10, PositionChangedReason.Liquidate)
        );

        // then maker and taker swap position and openNotional
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 0, positionSize: 10, openNotional: -10, unsettledPnl: 0 })
        );
        _assertEq(
            _getPosition(marketId, maker),
            PositionProfile({ margin: 0, positionSize: -10, openNotional: 10, unsettledPnl: 0 })
        );
    }

    function test_TakerIncreasePosition() public {
        // given taker margin=100, size=10, openNotional=-20 (avg $2)
        _set_position(taker, maker, 100, 10, -20);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(maker),
            address(maker),
            -20,
            10,
            0,
            PositionChangedReason.Trade
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(maker),
            20,
            -10,
            0,
            PositionChangedReason.Liquidate
        );

        // when clearingHouse settle, taker increase 20 long position at avg price $0.5
        vm.prank(mockClearingHouse);
        vault.settlePosition(
            IVault.SettlePositionParams(marketId, taker, maker, 20, -10, PositionChangedReason.Liquidate)
        );

        // then taker margin=100 size=10+20=30, openNotional=-20-10=-30
        // avg price after = $1
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 100, positionSize: 30, openNotional: -30, unsettledPnl: 0 })
        );
    }

    function test_TakerReducePosition() public {
        // given taker margin=100, size=10, openNotional=-20 (avg $2)
        _set_position(taker, maker, 100, 10, -20);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(maker),
            address(maker),
            5,
            -5,
            5,
            PositionChangedReason.Trade
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(maker),
            -5,
            5,
            -5,
            PositionChangedReason.Liquidate
        );

        // when clearingHouse settle, taker reduce 5 long
        // reduce 5/10=50%, reducedOpenNotional=-20*50%=-10, returnQuote=-5, realizedPnl=-5
        vm.prank(mockClearingHouse);
        vault.settlePosition(
            IVault.SettlePositionParams(marketId, taker, maker, -5, 5, PositionChangedReason.Liquidate)
        );

        // then taker margin=100-5(realizedPnl)=95 size=10-5=5
        // openNotional=-20+5(settleOpenNotional)+5(realizedPnl)=-10
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 95, positionSize: 5, openNotional: -10, unsettledPnl: 0 })
        );
    }

    function test_TakerCloseAndIncreaseReversePosition() public {
        // given taker margin=100, size=10, openNotional=-20 (avg $2)
        _set_position(taker, maker, 100, 10, -20);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(maker),
            address(maker),
            20,
            -20,
            10,
            PositionChangedReason.Trade
        );
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPositionModelEvent.PositionChanged(
            marketId,
            address(taker),
            address(maker),
            -20,
            20,
            -10,
            PositionChangedReason.Liquidate
        );

        // when settle, taker short 20 at openNotional = 20 (avg $1)
        vm.prank(mockClearingHouse);
        vault.settlePosition(
            IVault.SettlePositionParams(marketId, taker, maker, -20, 20, PositionChangedReason.Liquidate)
        );

        // then means taker closed position (realizedPnl=-10) & increase short 10 at openNotional 10
        // taker margin=100-10(realizedPnl)=90 size=10-20=-10 openNotional=10
        _assertEq(
            _getPosition(marketId, taker),
            PositionProfile({ margin: 90, positionSize: -10, openNotional: 10, unsettledPnl: 0 })
        );
    }

    function test_RevertIf_ZeroAmount() public {
        vm.prank(mockClearingHouse);
        vm.expectRevert(LibError.ZeroAmount.selector);
        vault.settlePosition(
            IVault.SettlePositionParams(marketId, taker, maker, 0, 20, PositionChangedReason.Liquidate)
        );
    }

    function test_RevertIf_NonClearingHouse() public {
        vm.prank(taker);
        vm.expectRevert(LibError.Unauthorized.selector);
        vault.settlePosition(
            IVault.SettlePositionParams(marketId, taker, maker, 1, 1, PositionChangedReason.Liquidate)
        );
    }

    function test_RevertIf_InvalidMarketId() public {
        vm.prank(mockClearingHouse);
        vm.expectRevert(abi.encodeWithSelector(LibError.InvalidMarket.selector, 123));
        vault.settlePosition(IVault.SettlePositionParams(123, taker, maker, 1, 1, PositionChangedReason.Liquidate));
    }
}
