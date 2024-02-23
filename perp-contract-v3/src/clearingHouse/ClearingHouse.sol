// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { LibFormatter } from "../common/LibFormatter.sol";
import { LibPosition } from "../vault/LibPosition.sol";
import { LibError } from "../common/LibError.sol";
import { INTERNAL_DECIMALS, WAD } from "../common/LibConstant.sol";
import { IMarginProfile, MarginRequirementType } from "../vault/IMarginProfile.sol";
import { Config } from "../config/Config.sol";
import { IMaker } from "../maker/IMaker.sol";
import { AuthorizationUpgradeable } from "../authorization/AuthorizationUpgradeable.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IVault } from "../vault/IVault.sol";
import { PositionChangedReason } from "../vault/PositionChangedReason.sol";
import { LibLiquidation, MaintenanceMarginProfile, LiquidationResult } from "./LibLiquidation.sol";

contract ClearingHouse is
    IClearingHouse,
    AuthorizationUpgradeable,
    AddressResolverUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using SafeCast for int256;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;
    using LibFormatter for uint256;
    using LibAddressResolver for IAddressManager;
    using LibLiquidation for MaintenanceMarginProfile;

    //
    // STRUCT
    //

    struct OpenPositionResult {
        int256 base;
        int256 quote;
        bool isTakerReducing;
        bool isMakerReducing;
    }

    struct EmitLiquidatedEventParams {
        uint256 marketId;
        address liquidator;
        address trader;
        int256 positionSizeDelta;
        int256 positionNotionalDelta;
        uint256 price;
        uint256 penalty;
        uint256 liquidationFeeToLiquidator;
        uint256 liquidationFeeToProtocol;
    }

    struct CheckMarginRequirementParams {
        IVault vault;
        uint256 marketId;
        address trader;
        uint256 price;
        bool isReducing;
    }

    //
    // MODIFIER
    //
    modifier nonZero(uint256 amount) {
        if (amount == 0) revert LibError.ZeroAmount();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) external initializer {
        __AddressResolver_init(addressManager);
        __Authorization_init();
        __ReentrancyGuard_init();
    }

    /// @inheritdoc IClearingHouse
    function openPosition(OpenPositionParams calldata params) external returns (int256, int256) {
        return _openPositionFor(_sender(), params);
    }

    /// @inheritdoc IClearingHouse
    function openPositionFor(OpenPositionForParams calldata params) external returns (int256, int256) {
        _checkIsSenderAuthorizedBy(params.taker);
        _chargeRelayFee(params.taker, params.takerRelayFee, params.maker, params.makerRelayFee);
        return
            _openPositionFor(
                params.taker,
                IClearingHouse.OpenPositionParams({
                    marketId: params.marketId,
                    maker: params.maker,
                    isBaseToQuote: params.isBaseToQuote,
                    isExactInput: params.isExactInput,
                    amount: params.amount,
                    oppositeAmountBound: params.oppositeAmountBound,
                    deadline: params.deadline,
                    makerData: params.makerData
                })
            );
    }

    /// @inheritdoc IClearingHouse
    function quoteOpenPosition(OpenPositionParams calldata params) external returns (int256, int256) {
        address taker = _sender();
        uint256 price = _getPrice(params.marketId);

        IVault vault = _getVault();
        OpenPositionResult memory result = _openPosition(vault, taker, params, PositionChangedReason.Trade);

        // Only check maker's margin is sufficient for filling order
        _checkMarginRequirement(
            CheckMarginRequirementParams({
                vault: vault,
                marketId: params.marketId,
                trader: params.maker,
                price: price,
                isReducing: result.isMakerReducing
            })
        );

        revert LibError.QuoteResult(result.base, result.quote);
    }

    /// @inheritdoc IClearingHouse
    function closePosition(ClosePositionParams calldata params) external returns (int256, int256) {
        return _closePositionFor(_sender(), params);
    }

    /// @inheritdoc IClearingHouse
    function closePositionFor(ClosePositionForParams calldata params) external returns (int256, int256) {
        _checkIsSenderAuthorizedBy(params.taker);
        _chargeRelayFee(params.taker, params.takerRelayFee, params.maker, params.makerRelayFee);
        return
            _closePositionFor(
                params.taker,
                IClearingHouse.ClosePositionParams({
                    marketId: params.marketId,
                    maker: params.maker,
                    oppositeAmountBound: params.oppositeAmountBound,
                    deadline: params.deadline,
                    makerData: params.makerData
                })
            );
    }

    /// @inheritdoc IClearingHouse
    function liquidate(
        LiquidatePositionParams calldata params
    ) external nonZero(params.positionSize) returns (int256, int256) {
        // We don't allow liquidating whitelisted makers for now until we implement safety mechanism
        // For spot-hedged base maker, it needs to implement rebalance once it got liquidated
        if (_isWhitelistedMaker(params.marketId, params.trader)) {
            revert LibError.CannotLiquidateWhitelistedMaker();
        }

        // calculate how much size can be liquidated, and how much open notional will be reduced correspondingly
        address liquidator = _sender();
        MaintenanceMarginProfile memory mmProfile = _getMaintenanceMarginProfile(
            params.marketId,
            params.trader,
            _getPrice(params.marketId)
        );
        LiquidationResult memory result = mmProfile.getLiquidationResult(params.positionSize);
        if (result.liquidatedPositionSizeDelta == 0) revert LibError.NotLiquidatable(params.marketId, params.trader);

        // settle to vault, pay out liquidation fee to liquidator and protocol
        IVault vault = _getVault();
        int256 liquidatorPositionSizeBefore = vault.getPositionSize(params.marketId, liquidator);
        vault.settlePosition(
            IVault.SettlePositionParams({
                marketId: params.marketId,
                taker: params.trader,
                maker: liquidator,
                takerPositionSize: result.liquidatedPositionSizeDelta,
                takerOpenNotional: result.liquidatedPositionNotionalDelta,
                reason: PositionChangedReason.Liquidate
            })
        );
        vault.transferMargin(params.marketId, params.trader, liquidator, result.feeToLiquidator);
        vault.transferMargin(params.marketId, params.trader, address(this), result.feeToProtocol);

        // always check margin in the end
        _checkMarginRequirement(
            CheckMarginRequirementParams({
                vault: vault,
                marketId: params.marketId,
                trader: liquidator,
                price: mmProfile.price,
                isReducing: LibPosition.isReduceOnly(
                    liquidatorPositionSizeBefore,
                    vault.getPositionSize(params.marketId, liquidator)
                )
            })
        );
        _emitLiquidatedEvent(
            EmitLiquidatedEventParams({
                marketId: params.marketId,
                liquidator: liquidator,
                trader: params.trader,
                positionSizeDelta: result.liquidatedPositionSizeDelta,
                positionNotionalDelta: result.liquidatedPositionNotionalDelta,
                price: mmProfile.price,
                penalty: result.penalty,
                liquidationFeeToLiquidator: result.feeToLiquidator,
                liquidationFeeToProtocol: result.feeToProtocol
            })
        );
        return (result.liquidatedPositionSizeDelta, result.liquidatedPositionNotionalDelta);
    }

    /// @dev in the beginning it only open for orderGateway & orderGatewayV2 to be authorized
    /// @inheritdoc AuthorizationUpgradeable
    function setAuthorization(address authorized, bool isAuthorized_) public override {
        IAddressManager addressManager = getAddressManager();
        if (
            isAuthorized_ &&
            authorized != address(addressManager.getOrderGateway()) &&
            authorized != address(addressManager.getOrderGatewayV2())
        ) {
            revert LibError.NotWhitelistedAuthorization();
        }
        super.setAuthorization(authorized, isAuthorized_);
    }

    //
    // EXTERNAL VIEW
    //

    /// @dev in order to throw decode error instead of panic, it must be in external call (or contract creation)
    /// @inheritdoc IClearingHouse
    function decodeMakerOrder(bytes calldata encoded) external pure returns (MakerOrder memory) {
        return abi.decode(encoded, (MakerOrder));
    }

    /// @inheritdoc IClearingHouse
    function isLiquidatable(uint256 marketId, address trader, uint256 price) external view returns (bool) {
        return _getLiquidatablePositionSize(marketId, trader, price) != 0;
    }

    /// @inheritdoc IClearingHouse
    function getLiquidatablePositionSize(
        uint256 marketId,
        address trader,
        uint256 price
    ) external view returns (int256) {
        return _getLiquidatablePositionSize(marketId, trader, price);
    }

    //
    // INTERNAL NON-VIEW
    //

    function _openPosition(
        IVault vault,
        address taker,
        OpenPositionParams memory params,
        PositionChangedReason reason
    ) internal nonZero(params.amount) returns (OpenPositionResult memory) {
        if (block.timestamp > params.deadline) revert LibError.DeadlineExceeded();

        // the amount maker is going to filled. could be base or quote based on taker's isExactInput & isBaseToQuote
        // currently only open whitelisted maker for callback. other maker must conforms the MakerOrder to quote price
        uint256 oppositeAmount;
        bytes memory callbackData;
        bool hasMakerCallback = _isWhitelistedMaker(params.marketId, params.maker);
        if (hasMakerCallback) {
            if (!IMaker(params.maker).isValidSender(msg.sender)) revert LibError.InvalidSender(msg.sender);
            (oppositeAmount, callbackData) = IMaker(params.maker).fillOrder(
                params.isBaseToQuote,
                params.isExactInput,
                params.amount,
                params.makerData
            );
        } else {
            // Note that params.maker here could be arbitrary account, so we do allow arbitrary account
            // to set arbitrary price when fillOrder.
            // However, we also check margin requirements with oracle price for both taker and maker after openPosition
            // FIXME: this is not enough, see OrderGatewayV2SettleOrderIntTest.test_SettleOrder_AtExtremePrice()
            _checkIsSenderAuthorizedBy(params.maker);
            try this.decodeMakerOrder(params.makerData) returns (MakerOrder memory makerOrder) {
                oppositeAmount = makerOrder.amount;
            } catch (bytes memory) {
                revert LibError.InvalidMakerData();
            }
            if (oppositeAmount == 0) revert LibError.InvalidMakerData();
        }

        // cache position size before mutation in order to detect whether it's reducing position.
        // caller has more flexibility to react - eg. give it lower margin requirement if it's reducing
        // NOTE: we assume IMaker.fillOrder() won't change any position state
        int256 takerPositionSizeBefore = vault.getPositionSize(params.marketId, taker);
        int256 makerPositionSizeBefore = vault.getPositionSize(params.marketId, params.maker);
        OpenPositionResult memory result;
        if (params.isExactInput) {
            _checkExactInputSlippage(oppositeAmount, params.oppositeAmountBound);
            if (params.isBaseToQuote) {
                // exactInput(base) to quote, B2Q base- quote+
                result.base = -params.amount.toInt256();
                result.quote = oppositeAmount.toInt256();
            } else {
                // exactInput(quote) to base, Q2B base+ quote-
                result.base = oppositeAmount.toInt256();
                result.quote = -params.amount.toInt256();
            }
        } else {
            _checkExactOutputSlippage(oppositeAmount, params.oppositeAmountBound);
            if (params.isBaseToQuote) {
                // base to exactOutput(quote), B2Q base- quote+
                result.base = -oppositeAmount.toInt256();
                result.quote = params.amount.toInt256();
            } else {
                // quote to exactOutput(base), Q2B base+ quote-
                result.base = params.amount.toInt256();
                result.quote = -oppositeAmount.toInt256();
            }
        }
        _checkPriceBand(params.marketId, result.quote.abs().divWad(result.base.abs()));

        result.isTakerReducing = LibPosition.isReduceOnly(
            takerPositionSizeBefore,
            takerPositionSizeBefore + result.base
        );
        result.isMakerReducing = LibPosition.isReduceOnly(
            makerPositionSizeBefore,
            makerPositionSizeBefore - result.base
        );
        vault.settlePosition(
            IVault.SettlePositionParams({
                marketId: params.marketId,
                taker: taker,
                maker: params.maker,
                takerPositionSize: result.base,
                takerOpenNotional: result.quote,
                reason: reason
            })
        );

        if (hasMakerCallback) {
            IMaker(params.maker).fillOrderCallback(callbackData);
        }
        return result;
    }

    function _openPositionFor(address taker, OpenPositionParams memory params) internal returns (int256, int256) {
        uint256 marketId = params.marketId;
        uint256 price = _getPrice(marketId);

        IVault vault = _getVault();
        OpenPositionResult memory result = _openPosition(vault, taker, params, PositionChangedReason.Trade);

        _checkMarginRequirement(
            CheckMarginRequirementParams({
                vault: vault,
                marketId: marketId,
                trader: taker,
                price: price,
                isReducing: result.isTakerReducing
            })
        );
        _checkMarginRequirement(
            CheckMarginRequirementParams({
                vault: vault,
                marketId: marketId,
                trader: params.maker,
                price: price,
                isReducing: result.isMakerReducing
            })
        );

        return (result.base, result.quote);
    }

    function _closePositionFor(address taker, ClosePositionParams memory params) internal returns (int256, int256) {
        uint256 marketId = params.marketId;
        uint256 price = _getPrice(marketId);
        IVault vault = _getVault();
        int256 positionSize = vault.getPositionSize(marketId, taker);
        bool isBaseToQuote = positionSize > 0;
        OpenPositionParams memory openPositionParams = OpenPositionParams({
            marketId: marketId,
            maker: params.maker,
            isBaseToQuote: isBaseToQuote,
            isExactInput: isBaseToQuote,
            amount: positionSize.abs(),
            oppositeAmountBound: params.oppositeAmountBound,
            deadline: params.deadline,
            makerData: params.makerData
        });
        OpenPositionResult memory result = _openPosition(vault, taker, openPositionParams, PositionChangedReason.Trade);

        _checkMarginRequirement(
            CheckMarginRequirementParams({
                vault: vault,
                marketId: marketId,
                trader: taker,
                price: price,
                isReducing: result.isTakerReducing
            })
        );
        _checkMarginRequirement(
            CheckMarginRequirementParams({
                vault: vault,
                marketId: marketId,
                trader: params.maker,
                price: price,
                isReducing: result.isMakerReducing
            })
        );

        return (result.base, result.quote);
    }

    /// @dev caller must ensure sender is already authorized by taker. we won't check sender's auth here because relay
    /// fee only comes from open/closePositionFor which already checked taker's auth
    function _chargeRelayFee(address taker, uint256 takerRelayFee, address maker, uint256 makerRelayFee) internal {
        IVault vault = _getVault();
        if (takerRelayFee > 0) {
            _checkRelayFee(taker, takerRelayFee);
            vault.transferFund(taker, msg.sender, takerRelayFee);
        }
        if (makerRelayFee > 0) {
            _checkIsSenderAuthorizedBy(maker);
            _checkRelayFee(maker, makerRelayFee);
            vault.transferFund(maker, msg.sender, makerRelayFee);
        }
    }

    /// @dev extract to a function for mitigating stack too deep error
    function _emitLiquidatedEvent(EmitLiquidatedEventParams memory params) internal {
        emit Liquidated(
            params.marketId,
            params.liquidator,
            params.trader,
            params.positionSizeDelta,
            params.positionNotionalDelta,
            params.price,
            params.penalty,
            params.liquidationFeeToLiquidator,
            params.liquidationFeeToProtocol
        );
    }

    //
    // INTERNAL VIEW
    //

    /// @notice trade price must be within the price band, which is the oracle price +/- priceBandRatio
    function _checkPriceBand(uint256 marketId, uint256 tradePrice) internal view {
        IAddressManager addressManager = getAddressManager();
        Config config = addressManager.getConfig();
        uint256 priceBandRatio = config.getPriceBandRatio(marketId);
        if (priceBandRatio == 0) {
            return;
        }
        bytes32 priceFeedId = config.getPriceFeedId(marketId);
        (uint256 oraclePrice, ) = addressManager.getPythOracleAdapter().getPrice(priceFeedId);
        uint256 upperPrice = oraclePrice.mulWad(WAD + priceBandRatio);
        uint256 lowerPrice = oraclePrice.mulWad(WAD - priceBandRatio);
        if (upperPrice < tradePrice || tradePrice < lowerPrice) {
            revert LibError.PriceOutOfBound(tradePrice, lowerPrice, upperPrice);
        }
    }

    function _checkIsSenderAuthorizedBy(address onBehalf) internal view {
        if (!isAuthorized(onBehalf, msg.sender)) revert LibError.AuthorizerNotAllow(onBehalf, msg.sender);
    }

    function _checkRelayFee(address trader, uint256 relayFee) internal view {
        Config config = getAddressManager().getConfig();
        uint256 maxRelayFee = config.getMaxRelayFee();
        if (relayFee > maxRelayFee) revert LibError.ExcessiveRelayFee(trader, msg.sender, relayFee, maxRelayFee);
    }

    function _checkMarginRequirement(CheckMarginRequirementParams memory params) internal view {
        // When increasing position:
        //   tradableCollateral(imRatio) must >= 0
        // When reducing position:
        //   tradableCollateral(mmRatio) must >= 0
        // When closing position:
        //   tradableCollateral(*) must >= 0 (*: it doesn't matter what ratio we put in because there are no positions remaining after close)
        IVault vault = params.vault;
        uint256 marketId = params.marketId;
        address trader = params.trader;
        uint256 price = params.price;
        if (params.isReducing) {
            // Reducing, Closing positions can share the same logic for now.
            int256 freeCollateralForReducingPosition = vault.getFreeCollateralForTrade(
                marketId,
                trader,
                price,
                MarginRequirementType.MAINTENANCE
            );
            if (freeCollateralForReducingPosition < 0) {
                revert LibError.NotEnoughFreeCollateral(marketId, trader);
            }
            return;
        }

        // is NOT reducing
        // Note that freeCollateralForOpen = tradableCollateral(imRatio)
        int256 freeCollateralForIncreasingPosition = vault.getFreeCollateralForTrade(
            marketId,
            trader,
            price,
            MarginRequirementType.INITIAL
        );
        if (freeCollateralForIncreasingPosition < 0) {
            revert LibError.NotEnoughFreeCollateral(marketId, trader);
        }
    }

    function _getVault() internal view returns (IVault) {
        return getAddressManager().getVault();
    }

    function _getPrice(uint256 marketId) internal view returns (uint256) {
        IAddressManager addressManager = getAddressManager();
        (uint256 price, ) = addressManager.getPythOracleAdapter().getPrice(
            addressManager.getConfig().getPriceFeedId(marketId)
        );
        return price;
    }

    function _isWhitelistedMaker(uint256 marketId, address trader) internal view returns (bool) {
        return getAddressManager().getConfig().isWhitelistedMaker(marketId, trader);
    }

    function _getLiquidatablePositionSize(
        uint256 marketId,
        address trader,
        uint256 price
    ) internal view returns (int256) {
        MaintenanceMarginProfile memory mmProfile = _getMaintenanceMarginProfile(marketId, trader, price);
        return mmProfile.getLiquidatablePositionSize();
    }

    function _getMaintenanceMarginProfile(
        uint256 marketId,
        address trader,
        uint256 price
    ) internal view returns (MaintenanceMarginProfile memory) {
        IAddressManager addressManager = getAddressManager();
        IVault vault = addressManager.getVault();
        int256 positionSize = vault.getPositionSize(marketId, trader);
        int256 openNotional = vault.getOpenNotional(marketId, trader);
        int256 maintenanceMarginRequirement = vault
            .getMarginRequirement(marketId, trader, MarginRequirementType.MAINTENANCE)
            .toInt256();
        int256 accountValue = vault.getAccountValue(marketId, trader, price);

        Config config = addressManager.getConfig();
        uint256 liquidationFeeRatio = config.getLiquidationFeeRatio(marketId);
        uint256 liquidationPenaltyRatio = config.getLiquidationPenaltyRatio(marketId);
        return
            MaintenanceMarginProfile({
                price: price,
                positionSize: positionSize,
                openNotional: openNotional,
                maintenanceMarginRequirement: maintenanceMarginRequirement,
                accountValue: accountValue,
                liquidationFeeRatio: liquidationFeeRatio,
                liquidationPenaltyRatio: liquidationPenaltyRatio
            });
    }

    //
    // INTERNAL PURE
    //
    function _checkExactInputSlippage(uint256 actual, uint256 target) internal pure {
        // want more output as possible, so we set a lower bound of output
        if (actual < target) {
            revert LibError.InsufficientOutputAmount(actual, target);
        }
    }

    function _checkExactOutputSlippage(uint256 actual, uint256 target) internal pure {
        // want less input as possible, so we set a upper bound of input
        if (actual > target) {
            revert LibError.ExcessiveInputAmount(actual, target);
        }
    }
}
