// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// solhint-disable-next-line max-line-length
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibFormatter } from "../common/LibFormatter.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { INTERNAL_DECIMALS, WAD } from "../common/LibConstant.sol";
import { LibError } from "../common/LibError.sol";
import { IMaker } from "./IMaker.sol";
import { IVault } from "../vault/IVault.sol";
import { ContextBase } from "../common/ContextBase.sol";
import { IPythOracleAdapter } from "../oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { IWhitelistLpManager } from "./IWhitelistLpManager.sol";

// Price from Pyth is predictable due to the latency between prices arriving at Pyth price service
// and those prices appearing on-chain.
// See https://sips.synthetix.io/sips/sip-285/#rationale
//
// This predictable price can be exploited by a front-runner, so any trade on OracleMaker must be 2-step, aka "delayed",
// and can only be interacted with through OrderGateway and OrderGatewayV2. This is configurable
// via OracleMaker.setValidSender().
contract OracleMaker is ContextBase, AddressResolverUpgradeable, Ownable2StepUpgradeable, ERC20Upgradeable, IMaker {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using SafeCast for int256;
    using FixedPointMathLib for uint256;
    using LibFormatter for uint256;
    using LibFormatter for int256;
    using LibAddressResolver for IAddressManager;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.oracleMaker
    struct OracleMakerStorage {
        uint256 marketId;
        bytes32 priceFeedId;
        /// @notice the minimum margin ratio required for trade or withdrawal
        uint256 minMarginRatio; // Min. marign ratio required by the maker at all time.
        /// @notice max spread ratio is the "given" in stoikov maker
        /// @dev price = maxSpreadRatio * positionRate
        /// @dev when maker has long, positionRate = min(100%, openNotional * minMarginRatio / freeCollateralForOpen)
        /// @dev when maker has short, positionRate = max(100%, openNotional * minMarginRatio / freeCollateralForOpen)
        uint256 maxSpreadRatio;
        mapping(address => bool) validSenderMap;
    }

    event Deposited(
        address depositor,
        uint256 shares, // Amount of share minted
        uint256 underlying // Amount of underlying token deposited
    );

    event Withdrawn(
        address withdrawer,
        uint256 shares, // Amount of shares burnt
        uint256 underlying // Amount of underlying tokens withdrawn
    );

    /// @notice Emitted when an order is being filled by a Pyth Oracle Maker.
    ///         It reveals all information associated to the trade price.
    event OMOrderFilled(
        uint256 marketId,
        uint256 oraclePrice, // In quote asset as wei, assume price >= 0
        int256 baseAmount, // Base token amount filled (from taker's perspective)
        int256 quoteAmount // Quote token amount filled (from taker's perspective)
    );

    event PriceFeedIdSet(bytes32 newPriceFeedId, bytes32 oldPriceFeedId);

    event MinMarginRatioSet(uint256 newMinMarginRatio, uint256 oldMinMarginRatio);
    event MaxSpreadRatioSet(uint256 newMaxSpreadRatio, uint256 oldMaxSpreadRatio);

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.oracleMaker")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _ORACLE_MAKER_STORAGE_LOCATION =
        0x49404affd0747f1de28f32f44120f8f18db1aa69644f83b133007475ed402e00;

    //
    // MODIFIER
    //
    modifier onlyClearingHouse() {
        if (msg.sender != address(getAddressManager().getClearingHouse())) revert LibError.Unauthorized();
        _;
    }

    modifier onlyWhitelistLp() {
        IWhitelistLpManager whitelistManager = getAddressManager().getWhitelistLpManager();
        if (address(whitelistManager) != address(0)) {
            if (!whitelistManager.isLpWhitelisted(_sender())) revert LibError.Unauthorized();
        }
        _;
    }

    //
    // EXTERNAL NON-VIEW
    //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 marketId_,
        string memory name_,
        string memory symbol_,
        address addressManager_,
        bytes32 priceFeedId_,
        uint256 minMarginRatio_
    ) external initializer {
        __AddressResolver_init(addressManager_);
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __ERC20_init(name_, symbol_);

        if (!getAddressManager().getPythOracleAdapter().priceFeedExists(priceFeedId_))
            revert LibError.IllegalPriceFeed(priceFeedId_);

        _getOracleMakerStorage().marketId = marketId_;
        setPriceFeedId(priceFeedId_);
        setMinMarginRatio(minMarginRatio_);
    }

    function setPriceFeedId(bytes32 _priceFeedId) public onlyOwner {
        if (!getAddressManager().getPythOracleAdapter().priceFeedExists(_priceFeedId))
            revert LibError.IllegalPriceFeed(_priceFeedId);

        bytes32 oldPriceFeedId = _getOracleMakerStorage().priceFeedId;
        _getOracleMakerStorage().priceFeedId = _priceFeedId;

        emit PriceFeedIdSet(_priceFeedId, oldPriceFeedId);
    }

    function setMinMarginRatio(uint256 _minMarginRatio) public onlyOwner {
        if (_minMarginRatio > WAD) {
            revert LibError.InvalidRatio(_minMarginRatio);
        }
        if (_minMarginRatio == 0) {
            revert LibError.ZeroRatio();
        }
        uint256 oldMinMarginRatio = _getOracleMakerStorage().minMarginRatio;
        _getOracleMakerStorage().minMarginRatio = _minMarginRatio;

        emit MinMarginRatioSet(_minMarginRatio, oldMinMarginRatio);
    }

    function setMaxSpreadRatio(uint256 _maxSpreadRatio) public onlyOwner {
        if (_maxSpreadRatio > WAD) {
            revert LibError.InvalidRatio(_maxSpreadRatio);
        }
        uint256 oldMaxSpreadRatio = _getOracleMakerStorage().maxSpreadRatio;
        _getOracleMakerStorage().maxSpreadRatio = _maxSpreadRatio;

        emit MaxSpreadRatioSet(_maxSpreadRatio, oldMaxSpreadRatio);
    }

    function setValidSender(address user, bool isValid) public onlyOwner {
        _getOracleMakerStorage().validSenderMap[user] = isValid;
    }

    function deposit(uint256 amountXCD) external onlyWhitelistLp returns (uint256) {
        address depositor = _sender();
        address maker = address(this);

        if (amountXCD == 0) revert LibError.ZeroAmount();

        IERC20Metadata collateralToken = IERC20Metadata(_getAsset());
        IAddressManager addressManager = getAddressManager();
        IVault vault = addressManager.getVault();

        uint256 shares;
        if (totalSupply() == 0) {
            shares = amountXCD;
        } else {
            uint256 price = _getPrice();

            // TODO Should consider slippage once maker has spread or other pricing logic.
            // For now, we will just get account value from ClearingHouse (assume no slippages).
            // shares per asset = share (share token precision) / accountValue (INTERNAL_DECIMALS)
            // shares (share token precision) = assets (base token precision) * shares per asset

            // TODO: We should add protections to prevent attackers from manipulating the share price by manipulating oracle reported price.
            // This is because the attacker could potentially mint large amount of shares by forcing the account value low.
            // Possible protections like rate limiting share price, or any kind of volatility check.

            uint8 shareDecimals = decimals();
            uint256 vaultValueXShareDecimals = _getVaultValueSafe(vault, price).formatDecimals(
                INTERNAL_DECIMALS,
                shareDecimals
            );
            uint256 amountXShareDecimals = amountXCD.formatDecimals(collateralToken.decimals(), shareDecimals);
            shares = (amountXShareDecimals * totalSupply()) / vaultValueXShareDecimals;
        }

        uint256 balanceBefore = collateralToken.balanceOf(maker);
        collateralToken.safeTransferFrom(_sender(), maker, amountXCD);
        uint256 transferredAmount = collateralToken.balanceOf(maker) - balanceBefore;

        if (transferredAmount != amountXCD) {
            revert LibError.WrongTransferAmount(transferredAmount, amountXCD);
        }

        collateralToken.approve(address(vault), amountXCD);
        vault.deposit(maker, amountXCD);
        vault.transferFundToMargin(_getOracleMakerStorage().marketId, amountXCD);

        _mint(depositor, shares);

        emit Deposited(depositor, shares, amountXCD);

        return shares;
    }

    function withdraw(uint256 shares) external onlyWhitelistLp returns (uint256) {
        address withdrawer = _sender();

        if (shares == 0) revert LibError.ZeroAmount();

        // Must done before burn.
        uint256 redeemedRatio = shares.divWad(totalSupply());

        // Revert early if shares amount exceeds balance
        _burn(withdrawer, shares);

        IVault vault = _getVault();

        uint256 price = _getPrice();
        uint256 vaultValue = _getVaultValueSafe(vault, price);
        IERC20Metadata collateralToken = IERC20Metadata(_getAsset());
        uint256 withdrawnAmountXCD = vaultValue.mulWad(redeemedRatio).formatDecimals(
            INTERNAL_DECIMALS,
            collateralToken.decimals()
        );

        // It may not be possible to withdraw the required amount, due to unsettledPnl that cannot be settled totally.
        vault.transferMarginToFund(_getOracleMakerStorage().marketId, withdrawnAmountXCD);
        vault.withdraw(withdrawnAmountXCD);
        collateralToken.safeTransfer(withdrawer, withdrawnAmountXCD);

        _checkMinMarginRatio(price);

        emit Withdrawn(withdrawer, shares, withdrawnAmountXCD);

        return withdrawnAmountXCD;
    }

    function fillOrderCallback(bytes calldata) external view onlyClearingHouse {
        _checkMinMarginRatio(_getPrice());
    }

    function fillOrder(
        bool isBaseToQuote,
        bool isExactInput,
        uint256 amount,
        bytes calldata
    ) external onlyClearingHouse returns (uint256, bytes memory) {
        uint256 basePrice = _getPrice();
        uint256 basePriceWithSpread = _getBasePriceWithSpread(basePrice, isBaseToQuote);

        // - `amount` base -> `amount * basePrice` quote
        //   (isBaseToQuote=true, isExactInput=true, openNotional = `amount * basePrice`)
        // - `amount` base <- `amount * basePrice` quote
        //   (isBaseToQuote=false, isExactInput=false, openNotional = -`amount * basePrice`)
        // - `amount / basePrice` base -> `amount` quote
        //   (isBaseToQuote=true, isExactInput=false, openNotional = `amount`)
        // - `amount / basePrice` base <- `amount` quote
        //   (isBaseToQuote=false, isExactInput=true, openNotional = -`amount`)

        int256 baseAmount;
        int256 quoteAmount;
        uint256 oppositeAmount;
        if (isBaseToQuote) {
            if (isExactInput) {
                // TODO: Should use configed decimal number instead of hard-coding
                oppositeAmount = (amount * basePriceWithSpread) / 1 ether;
                baseAmount = -amount.toInt256();
                quoteAmount = oppositeAmount.toInt256();
            } else {
                oppositeAmount = (amount * 1 ether) / basePriceWithSpread;
                baseAmount = -oppositeAmount.toInt256();
                quoteAmount = amount.toInt256();
            }
        } else {
            if (isExactInput) {
                oppositeAmount = (amount * 1 ether) / basePriceWithSpread;
                baseAmount = oppositeAmount.toInt256();
                quoteAmount = -amount.toInt256();
            } else {
                oppositeAmount = (amount * basePriceWithSpread) / 1 ether;
                baseAmount = amount.toInt256();
                quoteAmount = -oppositeAmount.toInt256();
            }
        }
        emit OMOrderFilled(_getOracleMakerStorage().marketId, basePrice, baseAmount, quoteAmount);
        return (oppositeAmount, new bytes(0));
    }

    //
    // EXTERNAL VIEW
    //

    function getUtilRatio() external view returns (uint256, uint256) {
        if (totalSupply() == 0) {
            return (0, 0);
        }

        IVault vault = _getVault();
        int256 positionSize = vault.getPositionSize(_getOracleMakerStorage().marketId, address(this));

        if (positionSize == 0) {
            return (0, 0);
        }

        uint256 price = _getPrice();
        int256 positionRate = _getPositionRate(price);
        // position rate > 0, maker has long position, set long util ratio to 0 so taker tends to long
        // position rate < 0, maker has short position, set short util ratio to 0 so taker tends to short
        return positionRate > 0 ? (uint256(0), positionRate.toUint256()) : ((-positionRate).toUint256(), uint256(0));
    }

    function isValidSender(address sender) external view returns (bool) {
        return _getOracleMakerStorage().validSenderMap[sender];
    }

    function getAsset() external view returns (address) {
        return _getAsset();
    }

    function getTotalAssets(uint256 price) external view returns (int256) {
        IVault vault = _getVault();
        IERC20Metadata collateralToken = IERC20Metadata(_getAsset());
        return _getVaultValue(vault, price).formatDecimals(INTERNAL_DECIMALS, collateralToken.decimals());
    }

    // For backward-compatibility
    function marketId() external view returns (uint256) {
        return _getOracleMakerStorage().marketId;
    }

    // For backward-compatibility
    function priceFeedId() external view returns (bytes32) {
        return _getOracleMakerStorage().priceFeedId;
    }

    // For backward-compatibility
    function minMarginRatio() external view returns (uint256) {
        return _getOracleMakerStorage().minMarginRatio;
    }

    // For backward-compatibility
    function maxSpreadRatio() external view returns (uint256) {
        return _getOracleMakerStorage().maxSpreadRatio;
    }

    //
    // INTERNAL VIEW
    //
    function _getVault() internal view returns (IVault) {
        return getAddressManager().getVault();
    }

    // FIXME: when over minMarginRatio, should allow reduce maker position
    function _checkMinMarginRatio(uint256 price) internal view {
        uint256 marketId_ = _getOracleMakerStorage().marketId;
        int256 marginRatio = _getVault().getMarginRatio(marketId_, address(this), price);
        int256 minMarginRatio_ = _getOracleMakerStorage().minMarginRatio.toInt256();
        if (marginRatio < minMarginRatio_) revert LibError.MinMarginRatioExceeded(marginRatio, minMarginRatio_);
    }

    function _getAsset() internal view returns (address) {
        return getAddressManager().getVault().getCollateralToken();
    }

    function _getVaultValue(IVault vault, uint256 price) internal view returns (int256) {
        uint256 marketId_ = _getOracleMakerStorage().marketId;
        return vault.getAccountValue(marketId_, address(this), price);
    }

    function _getVaultValueSafe(IVault vault, uint256 price) internal view returns (uint256) {
        // Revert early since we don't allow deposit/withdraw when the vault's value is negative or zero.
        int256 vaultValue = _getVaultValue(vault, price);
        if (vaultValue <= 0) revert LibError.NegativeOrZeroVaultValueInQuote(vaultValue);

        return vaultValue.toUint256();
    }

    function _getBasePriceWithSpread(uint256 basePrice, bool isBaseToQuote) internal view returns (uint256) {
        int256 positionRate = _getPositionRate(basePrice);
        int256 spreadRatio = (_getOracleMakerStorage().maxSpreadRatio.toInt256() * positionRate) / 1 ether;
        uint256 reservationPrice = (basePrice * (1 ether - spreadRatio).toUint256()) / 1 ether;
        return
            isBaseToQuote
                ? FixedPointMathLib.min(basePrice, reservationPrice)
                : FixedPointMathLib.max(basePrice, reservationPrice);
    }

    function _getPositionRate(uint256 price) internal view returns (int256) {
        IVault vault = _getVault();
        uint256 marketId_ = _getOracleMakerStorage().marketId;
        int256 accountValue = vault.getAccountValue(marketId_, address(this), price);
        int256 unrealizedPnl = vault.getUnrealizedPnl(marketId_, address(this), price);
        int256 unsettledMargin = accountValue - unrealizedPnl;
        int256 collateralForOpen = FixedPointMathLib.min(unsettledMargin, accountValue);
        // TODO: use positionMarginRequirement
        //int256 collateralForOpen = positionMarginRequirement + freeCollateralForOpen;
        if (collateralForOpen <= 0) {
            revert LibError.NegativeOrZeroMargin();
        }

        int256 maxPositionNotional = (collateralForOpen * 1 ether) / _getOracleMakerStorage().minMarginRatio.toInt256();

        // if maker has long position, positionRate > 0
        // if maker has short position, positionRate < 0
        int256 openNotional = vault.getOpenNotional(marketId_, address(this));
        int256 uncappedPositionRate = (-openNotional * 1 ether) / maxPositionNotional;

        // util ratio: 0 ~ 1
        // position rate: -1 ~ 1
        return
            uncappedPositionRate > 0
                ? FixedPointMathLib.min(uncappedPositionRate, 1 ether)
                : FixedPointMathLib.max(uncappedPositionRate, -1 ether);
    }

    function _getPrice() internal view returns (uint256) {
        IPythOracleAdapter pythOracleAdapter = getAddressManager().getPythOracleAdapter();
        (uint256 price, ) = pythOracleAdapter.getPrice(_getOracleMakerStorage().priceFeedId);
        return price;
    }

    //
    // PRIVATE
    //

    function _getOracleMakerStorage() private pure returns (OracleMakerStorage storage $) {
        assembly {
            $.slot := _ORACLE_MAKER_STORAGE_LOCATION
        }
    }
}
