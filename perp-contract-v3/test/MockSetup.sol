// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Config } from "../src/config/Config.sol";
import { AddressManager } from "../src/addressManager/AddressManager.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Vault } from "../src/vault/Vault.sol";
import { IMarginProfile } from "../src/vault/IMarginProfile.sol";
import { FundingFee } from "../src/fundingFee/FundingFee.sol";
import { BorrowingFee } from "../src/borrowingFee/BorrowingFee.sol";
import { IMaker } from "../src/maker/IMaker.sol";
import "./BaseTest.sol";

contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
}

contract MockSetup is BaseTest {
    uint256 marketId = 0;
    address public mockVault = makeAddr("vault");
    address public mockAddressManager = makeAddr("addressManager");
    address public mockClearingHouse = makeAddr("clearingHouse");
    address public mockOrderGateway = makeAddr("orderGateway");
    address public mockConfig = makeAddr("config");
    address public mockMakerReporter = makeAddr("makerReporter");
    address public mockBorrowingFee = makeAddr("borrowingFee");
    address public mockFundingFee = makeAddr("fundingFee");
    address public collateralToken = address(new TestERC20("Collateral Token", "USD"));
    address public mockOracleAdapter = makeAddr("PythOracleAdapter");
    bytes32 priceFeedId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    function test_excludeFromCoverageReport() public virtual override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function setUp() public virtual {
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, VAULT),
            abi.encode(mockVault)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, CLEARING_HOUSE),
            abi.encode(mockClearingHouse)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, ORDER_GATEWAY),
            abi.encode(mockOrderGateway)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, PYTH_ORACLE_ADAPTER),
            abi.encode(mockOracleAdapter)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, CONFIG),
            abi.encode(mockConfig)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, MAKER_REPORTER),
            abi.encode(mockMakerReporter)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, BORROWING_FEE),
            abi.encode(mockBorrowingFee)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, FUNDING_FEE),
            abi.encode(mockFundingFee)
        );
        vm.mockCall(
            mockAddressManager,
            abi.encodeWithSelector(AddressManager.getAddress.selector, WHITELIST_LP_MANAGER),
            abi.encode(address(0)) // default address(0) means no check whitelist lp
        );

        // only has 1 priceFeedId
        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.getPriceFeedId.selector), abi.encode(0x0));
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.getPriceFeedId.selector, marketId),
            abi.encode(priceFeedId)
        );
        vm.mockCall(
            mockOracleAdapter,
            abi.encodeWithSelector(IPythOracleAdapter.priceFeedExists.selector, priceFeedId),
            abi.encode(true)
        );

        // mock vault's collateral token
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getCollateralToken.selector), abi.encode(collateralToken));

        // mock vault getter
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getPositionSize.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getOpenNotional.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getUnrealizedPnl.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getAccountValue.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getMargin.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getMarginRatio.selector), abi.encode(0));
        vm.mockCall(mockVault, abi.encodeWithSelector(IMarginProfile.getFreeCollateral.selector), abi.encode(0));
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IMarginProfile.getFreeCollateralForTrade.selector),
            abi.encode(0)
        );

        // pnl pool balance = 0
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getPnlPoolBalance.selector, marketId), abi.encode(0));

        // initMarginRaito = 10%
        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.getInitialMarginRatio.selector), abi.encode(0.1e18));

        // maintenanceMarginRaito = 6.25%
        vm.mockCall(
            mockConfig,
            abi.encodeWithSelector(Config.getMaintenanceMarginRatio.selector),
            abi.encode(0.0625e18)
        );

        // max depositCap
        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.getDepositCap.selector), abi.encode(type(uint256).max));

        // assume 0 pending borrowing fee
        vm.mockCall(
            mockBorrowingFee,
            abi.encodeWithSelector(BorrowingFee.beforeSettlePosition.selector),
            abi.encode(0, 0)
        );
        vm.mockCall(
            mockBorrowingFee,
            abi.encodeWithSelector(BorrowingFee.beforeUpdateMargin.selector),
            abi.encode(0, 0)
        );
        vm.mockCall(mockBorrowingFee, abi.encodeWithSelector(BorrowingFee.getPendingFee.selector), abi.encode(0));

        // assume 0 pending funding fee
        vm.mockCall(mockFundingFee, abi.encodeWithSelector(FundingFee.beforeSettlePosition.selector), abi.encode(0, 0));
        vm.mockCall(mockFundingFee, abi.encodeWithSelector(FundingFee.beforeUpdateMargin.selector), abi.encode(0, 0));
        vm.mockCall(mockFundingFee, abi.encodeWithSelector(FundingFee.getPendingFee.selector), abi.encode(0));
    }
}
