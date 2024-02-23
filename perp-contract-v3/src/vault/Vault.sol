// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { LibFormatter } from "../common/LibFormatter.sol";
import { LibError } from "../common/LibError.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { INTERNAL_DECIMALS, WAD } from "../common/LibConstant.sol";
import { PositionChangedReason } from "./PositionChangedReason.sol";
import { MarginProfile } from "./MarginProfile.sol";
import { AuthorizationUpgradeable } from "../authorization/AuthorizationUpgradeable.sol";
import { PositionModelUpgradeable } from "./PositionModelUpgradeable.sol";
import { FundModelUpgradeable } from "./FundModelUpgradeable.sol";
import { IBorrowingFee } from "../borrowingFee/IBorrowingFee.sol";
import { IFundingFee } from "../fundingFee/IFundingFee.sol";
import { IVault, IMarginProfile } from "./IVault.sol";
import { ISystemStatus } from "../systemStatus/ISystemStatus.sol";
import { ICircuitBreaker } from "../circuitBreaker/ICircuitBreaker.sol";
import { Config } from "../config/Config.sol";

contract Vault is
    IVault,
    MarginProfile,
    PositionModelUpgradeable,
    FundModelUpgradeable,
    AuthorizationUpgradeable,
    AddressResolverUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using LibAddressResolver for IAddressManager;
    using LibFormatter for int256;
    using LibFormatter for uint256;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.vault
    struct VaultStorage {
        address collateralToken;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.vault")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _VAULT_STORAGE_LOCATION = 0x85f90adc629b3679eedec6d09e56cd525085826b30898500bd10fec0ebb20400;

    //
    // MODIFIER
    //

    modifier onlyClearingHouse() {
        if (msg.sender != address(getAddressManager().getClearingHouse())) revert LibError.Unauthorized();
        _;
    }

    modifier marketExistsAndActive(uint256 marketId) {
        if (getAddressManager().getConfig().getPriceFeedId(marketId) == 0x0) revert LibError.InvalidMarket(marketId);
        _getSystemStatus().requireMarketActive(marketId);
        _;
    }

    modifier nonZero(uint256 amount) {
        if (amount == 0) revert LibError.ZeroAmount();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager, address collateralToken) external initializer {
        __AddressResolver_init(addressManager);
        __ReentrancyGuard_init();
        __Authorization_init();
        __PositionModel_init();
        __FundModel_init();
        _getVaultStorage().collateralToken = collateralToken;
    }

    /// @inheritdoc IVault
    function deposit(address trader, uint256 amountXCD) external nonZero(amountXCD) nonReentrant {
        _getSystemStatus().requireSystemActive();

        _transferCollateralIn(_sender(), address(this), amountXCD);
        _updateFund(trader, amountXCD.toInt256());
        _checkDepositCap();
    }

    /// @inheritdoc IVault
    function withdraw(uint256 amountXCD) external nonZero(amountXCD) nonReentrant {
        _getSystemStatus().requireSystemActive();

        address trader = _sender();
        _updateFund(trader, -amountXCD.toInt256());

        // revert if hit withdrawal rate limit
        // we don't use the lockedFund-related features in Circuit Breaker for now
        _transferCollateralOut(trader, amountXCD, true);
    }

    /// @inheritdoc IVault
    function transferFundToMargin(uint256 marketId, uint256 amountXCD) external nonReentrant {
        address trader = _sender();
        _transferFundToMargin(marketId, trader, amountXCD);
    }

    /// @inheritdoc IVault
    function transferFundToMargin(uint256 marketId, address trader, uint256 amountXCD) external nonReentrant {
        _checkIsSenderAuthorized(trader);
        _transferFundToMargin(marketId, trader, amountXCD);
    }

    /// @inheritdoc IVault
    function transferMarginToFund(uint256 marketId, uint256 amountXCD) external nonReentrant {
        address trader = _sender();
        _transferMarginToFund(marketId, trader, amountXCD);
    }

    /// @inheritdoc IVault
    function transferMarginToFund(uint256 marketId, address trader, uint256 amountXCD) external nonReentrant {
        _checkIsSenderAuthorized(trader);
        _transferMarginToFund(marketId, trader, amountXCD);
    }

    // ClearingHouse.openPosition() will call Vault.settlePosition()
    /// @inheritdoc IVault
    function settlePosition(
        SettlePositionParams calldata params
    ) external override nonReentrant onlyClearingHouse marketExistsAndActive(params.marketId) {
        if (params.takerPositionSize == 0) revert LibError.ZeroAmount();

        // before hook
        int256 takerPendingMargin;
        int256 makerPendingMargin;
        IBorrowingFee borrowingFee = _getBorrowingFee();
        bool hasBorrowingFee = address(borrowingFee) != address(0);
        if (hasBorrowingFee) {
            (int256 takerBorrowingFee, int256 makerBorrowingFee) = borrowingFee.beforeSettlePosition(
                params.marketId,
                params.taker,
                params.maker,
                params.takerPositionSize,
                params.takerOpenNotional
            );
            takerPendingMargin -= takerBorrowingFee;
            makerPendingMargin -= makerBorrowingFee;
        }
        IFundingFee fundingFee = _getFundingFee();
        if (address(fundingFee) != address(0)) {
            (int256 takerFundingFee, int256 makerFundingFee) = fundingFee.beforeSettlePosition(
                params.marketId,
                params.taker,
                params.maker
            );
            takerPendingMargin -= takerFundingFee;
            makerPendingMargin -= makerFundingFee;
        }
        // settle taker & maker's pending margin
        if (takerPendingMargin != 0) {
            _settlePnl(params.marketId, params.taker, takerPendingMargin);
        }
        if (makerPendingMargin != 0) {
            _settlePnl(params.marketId, params.maker, makerPendingMargin);
        }

        // settle maker first, let taker can settle unsettledPnl as much as possible
        _addPosition(
            // Note: for maker, the reason for PositionChanged is always `Trade` because he is the counter-party
            AddPositionParams({
                marketId: params.marketId,
                trader: params.maker,
                maker: params.maker,
                positionSizeDelta: -params.takerPositionSize,
                openNotionalDelta: -params.takerOpenNotional,
                reason: PositionChangedReason.Trade
            })
        );
        _addPosition(
            AddPositionParams({
                marketId: params.marketId,
                trader: params.taker,
                maker: params.maker,
                positionSizeDelta: params.takerPositionSize,
                openNotionalDelta: params.takerOpenNotional,
                reason: params.reason
            })
        );

        // after hook
        if (hasBorrowingFee) {
            borrowingFee.afterSettlePosition(params.marketId, params.maker);
        }
    }

    /// @inheritdoc IVault
    function transferFund(address from, address to, uint256 amountXCD) external onlyClearingHouse {
        _updateFund(from, -amountXCD.toInt256());
        _updateFund(to, amountXCD.toInt256());
    }

    /// @inheritdoc IVault
    function transferMargin(
        uint256 marketId,
        address from,
        address to,
        uint256 amount
    ) external marketExistsAndActive(marketId) onlyClearingHouse {
        _settlePnl(marketId, from, -(amount.toInt256()));
        _settlePnl(marketId, to, amount.toInt256());
    }

    //
    // PUBLIC
    //

    /// @dev in the beginning it only open for orderGateway & orderGatewayV2 to be authorized
    /// @inheritdoc AuthorizationUpgradeable
    function setAuthorization(address authorized, bool isAuthorized_) public override {
        if (
            isAuthorized_ &&
            authorized != address(getAddressManager().getOrderGateway()) &&
            authorized != address(getAddressManager().getOrderGatewayV2())
        ) {
            revert LibError.NotWhitelistedAuthorization();
        }
        super.setAuthorization(authorized, isAuthorized_);
    }

    //
    // EXTERNAL VIEW
    //

    function getUnsettledPnl(uint256 marketId, address trader) external view returns (int256) {
        return _getUnsettledPnl(marketId, trader);
    }

    function getFund(address trader) external view returns (uint256) {
        return _getFund(trader);
    }

    function getSettledMargin(uint256 marketId, address trader) external view returns (int256) {
        return _getSettledMargin(marketId, trader);
    }

    function getCollateralToken() external view returns (address) {
        return _getVaultStorage().collateralToken;
    }

    //
    // PUBLIC VIEW
    //

    /// @inheritdoc MarginProfile
    /// @dev margin = settledMargin + unsettledPnl
    function getMargin(
        uint256 marketId,
        address trader
    ) public view override(IMarginProfile, MarginProfile) returns (int256) {
        return _getSettledMargin(marketId, trader) + getPendingMargin(marketId, trader);
    }

    /// @inheritdoc MarginProfile
    /// @dev free margin = max(margin state + pending margin + settleable unsettled pnl, 0)
    function getFreeMargin(
        uint256 marketId,
        address trader
    ) public view override(IMarginProfile, MarginProfile) returns (uint256) {
        int256 pendingMargin = getPendingMargin(marketId, trader);
        return _getFreeMargin(marketId, trader, pendingMargin);
    }

    /// @inheritdoc MarginProfile
    function getPositionSize(
        uint256 marketId,
        address trader
    ) public view override(IMarginProfile, MarginProfile) returns (int256) {
        return _getPositionSize(marketId, trader);
    }

    /// @inheritdoc MarginProfile
    function getOpenNotional(
        uint256 marketId,
        address trader
    ) public view override(IMarginProfile, MarginProfile) returns (int256) {
        return _getOpenNotional(marketId, trader);
    }

    /// @dev returning marginDelta, but fee is negative, reverse the sign
    function getPendingMargin(uint256 marketId, address trader) public view returns (int256) {
        int256 pendingMargin;
        IBorrowingFee borrowingFee = _getBorrowingFee();
        if (address(borrowingFee) != address(0)) {
            pendingMargin -= borrowingFee.getPendingFee(marketId, trader);
        }
        IFundingFee fundingFee = _getFundingFee();
        if (address(fundingFee) != address(0)) {
            pendingMargin -= fundingFee.getPendingFee(marketId, trader);
        }
        return pendingMargin;
    }

    function getPnlPoolBalance(uint256 marketId) public view returns (uint256) {
        return _getPnlPoolBalance(marketId);
    }

    function getBadDebt(uint256 marketId) public view returns (uint256) {
        return _getBadDebt(marketId);
    }

    //
    // INTERNAL
    //

    function _transferCollateralIn(address sender, address recipient, uint256 amountXCD) internal {
        IERC20Metadata collateralToken = IERC20Metadata(_getVaultStorage().collateralToken);
        uint256 balanceBefore = collateralToken.balanceOf(recipient);
        collateralToken.safeTransferFrom(sender, recipient, amountXCD);
        uint256 transferredAmountXCD = collateralToken.balanceOf(recipient) - balanceBefore;
        if (transferredAmountXCD != amountXCD) {
            revert LibError.MismatchedTransferAmount(transferredAmountXCD, amountXCD);
        }

        ICircuitBreaker circuitBreaker = _getCircuitBreaker();

        if (address(circuitBreaker) != address(0)) {
            // update CircuitBreaker rate limit status
            circuitBreaker.onTokenInflow(address(collateralToken), amountXCD);
        }
    }

    function _transferCollateralOut(address recipient, uint256 amountXCD, bool revertOnRateLimit) internal {
        ICircuitBreaker circuitBreaker = _getCircuitBreaker();
        address collateralToken = _getVaultStorage().collateralToken;

        if (address(circuitBreaker) != address(0)) {
            IERC20Metadata(collateralToken).safeTransfer(address(circuitBreaker), amountXCD);

            // update/check CircuitBreaker rate limit status
            circuitBreaker.onTokenOutflow(collateralToken, amountXCD, recipient, revertOnRateLimit);
        } else {
            IERC20Metadata(collateralToken).safeTransfer(recipient, amountXCD);
        }
    }

    /// @param marginDeltaXCD in collateral's decimals, trader's perspective
    function _formatAndUpdateMargin(uint256 marketId, address trader, int256 marginDeltaXCD) internal {
        // before hook
        int256 pendingMargin;
        IBorrowingFee borrowingFee = _getBorrowingFee();
        bool hasBorrowingFee = address(borrowingFee) != address(0);
        if (hasBorrowingFee) {
            int256 pendingBorrowingFee = borrowingFee.beforeUpdateMargin(marketId, trader);
            pendingMargin -= pendingBorrowingFee;
        }
        IFundingFee fundingFee = _getFundingFee();
        if (address(fundingFee) != address(0)) {
            int256 pendingFundingFee = fundingFee.beforeUpdateMargin(marketId, trader);
            pendingMargin -= pendingFundingFee;
        }
        if (pendingMargin != 0) {
            _settlePnl(marketId, trader, pendingMargin);
        }

        // update margin
        uint8 collateralDecimals = IERC20Metadata(_getVaultStorage().collateralToken).decimals();
        int256 marginDelta = marginDeltaXCD.formatDecimals(collateralDecimals, INTERNAL_DECIMALS);
        _updateMargin(marketId, trader, marginDelta);

        // after hook
        if (hasBorrowingFee) {
            borrowingFee.afterUpdateMargin(marketId, trader);
        }
    }

    /// @param amountXCD in collateral's decimals
    function _transferFundToMargin(
        uint256 marketId,
        address trader,
        uint256 amountXCD
    ) internal marketExistsAndActive(marketId) {
        if (amountXCD == 0) {
            revert LibError.ZeroAmount();
        }

        _updateFund(trader, -amountXCD.toInt256());

        // update accounting
        _formatAndUpdateMargin(marketId, trader, amountXCD.toInt256());

        // repay from margin right away if there's any unsettled loss before
        _settlePnl(marketId, trader, 0);
    }

    function _transferMarginToFund(
        uint256 marketId,
        address trader,
        uint256 amountXCD
    ) internal marketExistsAndActive(marketId) {
        if (amountXCD == 0) {
            revert LibError.ZeroAmount();
        }

        // check free collateral is enough for withdraw
        uint256 price = _getPrice(marketId);
        uint256 freeCollateral = getFreeCollateral(marketId, trader, price);

        //  convert margin from collateral decimals to INTERNAL_DECIMALS for comparison
        IERC20Metadata collateralToken = IERC20Metadata(_getVaultStorage().collateralToken);
        uint256 amount = amountXCD.formatDecimals(collateralToken.decimals(), INTERNAL_DECIMALS);
        if (freeCollateral < amount) {
            revert LibError.NotEnoughFreeCollateral(marketId, trader);
        }

        // repay from margin first if there's any unsettled loss before
        _settlePnl(marketId, trader, 0);

        // update accounting
        _formatAndUpdateMargin(marketId, trader, -amountXCD.toInt256());

        _updateFund(trader, amountXCD.toInt256());
    }

    //
    // INTERNAL VIEW
    //

    /// @inheritdoc MarginProfile
    function _getInitialMarginRatio(uint256 marketId) internal view override returns (uint256) {
        return _getConfig().getInitialMarginRatio(marketId);
    }

    /// @inheritdoc MarginProfile
    function _getMaintenanceMarginRatio(uint256 marketId) internal view override returns (uint256) {
        return _getConfig().getMaintenanceMarginRatio(marketId);
    }

    function _getConfig() internal view returns (Config) {
        return getAddressManager().getConfig();
    }

    function _getBorrowingFee() internal view returns (IBorrowingFee) {
        return getAddressManager().getBorrowingFee();
    }

    function _getFundingFee() internal view returns (IFundingFee) {
        return getAddressManager().getFundingFee();
    }

    function _getSystemStatus() internal view returns (ISystemStatus) {
        return getAddressManager().getSystemStatus();
    }

    function _getCircuitBreaker() internal view returns (ICircuitBreaker) {
        return getAddressManager().getCircuitBreaker();
    }

    function _checkIsSenderAuthorized(address onBehalf) internal view {
        if (!isAuthorized(onBehalf, msg.sender)) revert LibError.AuthorizerNotAllow(onBehalf, msg.sender);
    }

    function _getPrice(uint256 marketId) internal view returns (uint256) {
        (uint256 price, ) = getAddressManager().getPythOracleAdapter().getPrice(
            getAddressManager().getConfig().getPriceFeedId(marketId)
        );
        return price;
    }

    function _checkDepositCap() internal view {
        uint256 depositCap = _getConfig().getDepositCap();
        if (IERC20Metadata(_getVaultStorage().collateralToken).balanceOf(address(this)) > depositCap) {
            revert LibError.DepositCapExceeded();
        }
    }

    //
    // PRIVATE
    //

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := _VAULT_STORAGE_LOCATION
        }
    }
}
