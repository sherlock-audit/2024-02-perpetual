// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../MockSetup.sol";
import { SystemStatus } from "../../src/systemStatus/SystemStatus.sol";
import "../../src/vault/IPositionModelEvent.sol";

contract VaultSpecSetup is MockSetup {
    Vault public vault;

    function setUp() public virtual override {
        super.setUp();

        vault = new Vault();
        _enableInitialize(address(vault));
        vault.initialize(mockAddressManager, collateralToken);

        // no whitelisted maker yet
        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.isWhitelistedMaker.selector), abi.encode(false));

        // mock SystemStatus to be active
        address mockedSystemStatus = makeAddr("mockedSystemStatus");
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, "SystemStatus"),
            abi.encode(mockedSystemStatus)
        );
        vm.mockCall(mockedSystemStatus, abi.encodeWithSelector(SystemStatus.requireSystemActive.selector), "");
        vm.mockCall(
            mockedSystemStatus,
            abi.encodeWithSelector(SystemStatus.requireMarketActive.selector, marketId),
            ""
        );

        // mock CircuitBreaker to be deactivate
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, "CircuitBreaker"),
            abi.encode(address(0))
        );
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    //
    // INTERNAL
    //
    function _deposit(address trader, uint256 amountXCD) internal {
        vm.startPrank(trader);
        deal(collateralToken, trader, amountXCD);
        ERC20(collateralToken).approve(address(vault), amountXCD);
        vault.deposit(trader, amountXCD);
        vm.stopPrank();
    }

    /// @notice can only set margin, size, openNotional if it's a empty position
    function _set_position(
        address trader,
        address maker,
        uint256 margin,
        int256 positionSize,
        int256 openNotional
    ) internal {
        require(vault.getMargin(marketId, trader) == 0);
        require(vault.getPositionSize(marketId, trader) == 0);
        require(vault.getOpenNotional(marketId, trader) == 0);

        uint8 collateralDecimals = ERC20(collateralToken).decimals();
        uint256 marginXCD = (margin * 10 ** collateralDecimals) / 1 ether;
        _deposit(trader, marginXCD);
        vm.prank(trader);
        vault.transferFundToMargin(marketId, marginXCD);

        if (positionSize == 0) {
            return;
        }
        vm.prank(mockClearingHouse);
        vault.settlePosition(
            IVault.SettlePositionParams(
                marketId,
                trader,
                maker,
                positionSize,
                openNotional,
                PositionChangedReason.Trade
            )
        );
    }

    function _getPosition(uint256 _marketId, address trader) internal view returns (PositionProfile memory) {
        return
            PositionProfile({
                margin: vault.getMargin(_marketId, trader),
                unsettledPnl: vault.getUnsettledPnl(_marketId, trader),
                positionSize: vault.getPositionSize(_marketId, trader),
                openNotional: vault.getOpenNotional(_marketId, trader)
            });
    }
}
