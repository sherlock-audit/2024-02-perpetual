// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// solhint-disable-next-line max-line-length
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { LibFormatter } from "../common/LibFormatter.sol";
import { LibError } from "../common/LibError.sol";
import { INTERNAL_DECIMALS, WAD } from "../common/LibConstant.sol";
import { IClearingHouse } from "../clearingHouse/IClearingHouse.sol";
import { Config } from "../config/Config.sol";
import { IVault } from "../vault/IVault.sol";
import { IMaker } from "../maker/IMaker.sol";
import { IPythOracleAdapter } from "../oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { ContextBase } from "../common/ContextBase.sol";
import { LibOrder } from "./LibOrder.sol";

// Unlike OrderGateway, all orders are stored off-chain in OrderGatewayV2, and only whitelisted matchers (relayers)
// can settle orders. This is configurable via OrderGatewayV2.setRelayer().
//
// We require any trade on OracleMaker must be 2-step in OrderGateway. However, we didn't have such requirements
// in OrderGatewayV2 since orders can only be settled by whitelisted matchers.
// TODO: Is this assumption safe enough to prevent front-running?
contract OrderGatewayV2 is EIP712Upgradeable, ContextBase, AddressResolverUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using LibAddressResolver for IAddressManager;
    using LibFormatter for *;
    using SafeCast for uint256;
    using SafeCast for int256;
    using FixedPointMathLib for int256;
    using LibOrder for Order;

    enum ActionType {
        OpenPosition,
        ReduceOnly
    }

    enum TradeType {
        PartialFill,
        FoK
    }

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.orderGatewayV2
    struct OrderGatewayV2Storage {
        mapping(address => bool) isRelayer;
        mapping(bytes32 => uint256) totalFilledAmount;
        mapping(bytes32 => bool) isMarginTransferred;
        mapping(bytes32 => bool) isRelayFeeTaken;
        mapping(bytes32 => bool) isOrderCanceled;
    }

    struct Order {
        ActionType action;
        uint256 marketId;
        int256 amount;
        uint256 price;
        uint256 expiry;
        TradeType tradeType;
        address owner;
        uint256 marginXCD;
        uint256 relayFee;
        bytes32 id;
    }

    struct SignedOrder {
        Order order;
        bytes signature;
    }

    struct SettleOrderParam {
        SignedOrder signedOrder;
        uint256 fillAmount;
        address maker;
        bytes makerData;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.orderGatewayV2")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _ORDER_GATEWAY_V2_STORAGE_LOCATION =
        0x16459c8cdc185adffd42f3aaeca8a1a10f7af2dfd66eb7d81c6f96679ffbde00;

    // keccak256 value: 0x112f24273953496214afa22f35960e8571a3ae064d87213f08f46499ee5faf09
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint8 action,uint256 marketId,int256 amount,uint256 price,uint256 expiry,uint8 tradeType,address owner,uint256 marginXCD,uint256 relayFee,bytes32 id)"
        );

    event OrderFilled(
        address indexed owner,
        bytes32 indexed orderId,
        ActionType action,
        TradeType tradeType,
        uint256 marketId,
        int256 amount,
        uint256 fillAmount,
        uint256 price,
        uint256 fillPrice,
        uint256 expiry,
        uint256 marginXCD,
        uint256 relayFee,
        address maker
    );

    event OrderCanceled(address indexed owner, bytes32 indexed id, string reason);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory version_, address addressManager_) external initializer {
        __AddressResolver_init(addressManager_);
        __ReentrancyGuard_init();
        __EIP712_init(name_, version_); // ex: "OrderGateway" and "1"
    }

    //
    // MODIFIER
    //
    modifier onlyOwner() {
        if (msg.sender != address(getAddressManager().getConfig().owner())) revert LibError.Unauthorized();
        _;
    }

    modifier onlyRelayer(address sender) {
        if (!_getOrderGatewayV2Storage().isRelayer[sender]) revert LibError.Unauthorized();
        _;
    }

    //
    // EXTERNAL NON VIEW
    //

    function setRelayer(address address_, bool isRelayer_) external onlyOwner {
        _getOrderGatewayV2Storage().isRelayer[address_] = isRelayer_;
    }

    // NOTE: matcherFee will managed by admin
    function withdrawMatcherFee() external onlyOwner {
        IVault vault = getAddressManager().getVault();
        vault.withdraw(vault.getFund(address(this)));
        IERC20Metadata collateralToken = IERC20Metadata(_getAsset(vault));
        collateralToken.safeTransfer(msg.sender, IERC20Metadata(collateralToken).balanceOf(address(this)));
    }

    function settleOrder(SettleOrderParam[] calldata settleOrderParams) external onlyRelayer(_sender()) nonReentrant {
        uint256 settleOrderParamsLength = settleOrderParams.length;

        // NOTE: only support 1 <-> 1 order matching for now
        if (settleOrderParamsLength != 1) {
            revert LibError.SettleOrderParamsLengthError();
        }

        IAddressManager addressManager = getAddressManager();
        IClearingHouse clearingHouse = addressManager.getClearingHouse();
        InternalContext memory context;
        // we cache some storage reads in "context" since we will use them multiple times in other internal functions
        context.vault = addressManager.getVault();
        context.config = addressManager.getConfig();
        context.pythOracleAdapter = addressManager.getPythOracleAdapter();
        context.collateralTokenDecimals = IERC20Metadata(_getAsset(context.vault)).decimals();

        for (uint256 i = 0; i < settleOrderParamsLength; i++) {
            SettleOrderParam memory settleOrderParam = settleOrderParams[i];
            uint256 marketId = settleOrderParam.signedOrder.order.marketId;
            context.imRatio = context.config.getInitialMarginRatio(marketId);
            context.oraclePrice = _getPrice(context.pythOracleAdapter, context.config, marketId);

            (InternalWithdrawMarginParam memory takerWithdrawMarginParam, uint256 takerRelayFee) = _fillTakerOrder(
                context,
                settleOrderParam
            );

            (
                bytes memory makerData,
                InternalWithdrawMarginParam memory makerWithdrawMarginParam,
                uint256 makerRelayFee
            ) = _fillMakerOrder(context, settleOrderParam);

            _openPosition(
                InternalOpenPositionParams({
                    clearingHouse: clearingHouse,
                    settleOrderParam: settleOrderParam,
                    makerData: makerData,
                    takerRelayFee: takerRelayFee,
                    makerRelayFee: makerRelayFee
                })
            );

            // withdraw margin for taker reduce order
            if (takerWithdrawMarginParam.trader != address(0)) {
                _withdrawMargin(
                    context,
                    marketId,
                    takerWithdrawMarginParam.trader,
                    takerWithdrawMarginParam.requiredMarginRatio
                );
            }

            // withdraw margin for maker reduce order
            if (makerWithdrawMarginParam.trader != address(0)) {
                _withdrawMargin(
                    context,
                    marketId,
                    makerWithdrawMarginParam.trader,
                    makerWithdrawMarginParam.requiredMarginRatio
                );
            }
        }
    }

    function cancelOrder(SignedOrder memory signedOrder) external {
        Order memory order = verifyOrderSignature(signedOrder);
        if (order.owner != _sender()) {
            revert LibError.Unauthorized();
        }

        // cannot use order.id as key, anyone can sign an arbitrary order and set order.id to other trader's order.id
        // since we didn't store the whole order on-chain
        _getOrderGatewayV2Storage().isOrderCanceled[order.getKey()] = true;
        emit OrderCanceled(order.owner, order.id, "Canceled");
    }

    //
    // EXTERNAL VIEW
    //

    function isRelayer(address address_) external view returns (bool) {
        return _getOrderGatewayV2Storage().isRelayer[address_];
    }

    //
    // PUBLIC VIEW
    //

    function isOrderCanceled(address orderOwner, bytes32 orderId) public view returns (bool) {
        bytes32 key = LibOrder.getOrderKey(orderOwner, orderId);
        return _getOrderGatewayV2Storage().isOrderCanceled[key];
    }

    function getOrderFilledAmount(address orderOwner, bytes32 orderId) public view returns (uint256) {
        bytes32 key = LibOrder.getOrderKey(orderOwner, orderId);
        return _getOrderGatewayV2Storage().totalFilledAmount[key];
    }

    function getOrderHash(Order memory order) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(ORDER_TYPEHASH, order)));
    }

    // TODO rename
    function verifyOrderSignature(SignedOrder memory signedOrder) public returns (Order memory) {
        Order memory order = signedOrder.order;
        bytes32 orderHash = getOrderHash(order);

        // UniversalSigValidator can verify the following signature types:
        // 1. EIP-712 signature (signed by an EOA)
        // 2. EIP-1271 signature (signed by a contract)
        // 3. EIP-6492 signature (signed by a contract which is not yet deployed)
        try
            getAddressManager().getUniversalSigValidator().isValidSig(order.owner, orderHash, signedOrder.signature)
        returns (bool isValidSig) {
            if (!isValidSig) {
                revert LibError.OrderSignatureOwnerError(order.owner, order.id, "Invalid signature");
            }
        } catch (bytes memory reason) {
            revert LibError.OrderSignatureOwnerError(order.owner, order.id, reason);
        }

        return order;
    }

    //
    // INTERNAL NON VIEW
    //

    struct InternalContext {
        IVault vault;
        Config config;
        IPythOracleAdapter pythOracleAdapter;
        uint256 imRatio;
        uint8 collateralTokenDecimals;
        uint256 oraclePrice;
    }

    /// @notice every order should only be took relay fee once
    /// @param order the order being charged matcher fee
    /// @return the actual fee it is going to ask ClearingHouse to pay for relaying the order
    function _takeRelayFee(Order memory order) internal returns (uint256) {
        bytes32 orderKey = order.getKey();
        if (!_getOrderGatewayV2Storage().isRelayFeeTaken[orderKey] && order.relayFee > 0) {
            _getOrderGatewayV2Storage().isRelayFeeTaken[orderKey] = true;
            return order.relayFee;
        }
        return 0;
    }

    function _transferFundToMargin(IVault vault, Order memory order) internal {
        bytes32 orderKey = order.getKey();
        if (!_getOrderGatewayV2Storage().isMarginTransferred[orderKey] && order.marginXCD > 0) {
            vault.transferFundToMargin(order.marketId, order.owner, order.marginXCD);
            _getOrderGatewayV2Storage().isMarginTransferred[orderKey] = true;
        }
    }

    struct InternalWithdrawMarginParam {
        address trader;
        uint256 requiredMarginRatio;
    }

    function _fillTakerOrder(
        InternalContext memory context,
        SettleOrderParam memory settleOrderParams
    ) internal returns (InternalWithdrawMarginParam memory, uint256) {
        Order memory takerOrder = verifyOrderSignature(settleOrderParams.signedOrder);

        _verifyOrder(context.vault, takerOrder, settleOrderParams.fillAmount);

        // deposit margin for taker
        _transferFundToMargin(context.vault, takerOrder);

        _getOrderGatewayV2Storage().totalFilledAmount[takerOrder.getKey()] += settleOrderParams.fillAmount;

        // withdraw margin only for reduceOnly order
        InternalWithdrawMarginParam memory withdrawParam;
        if (takerOrder.action == ActionType.ReduceOnly) {
            withdrawParam.trader = takerOrder.owner;
            withdrawParam.requiredMarginRatio = FixedPointMathLib
                .max(context.vault.getMarginRatio(takerOrder.marketId, takerOrder.owner, context.oraclePrice), 0)
                .toUint256();
        }

        return (withdrawParam, _takeRelayFee(takerOrder));
    }

    function _fillMakerOrder(
        InternalContext memory context,
        SettleOrderParam memory settleOrderParams
    ) internal returns (bytes memory, InternalWithdrawMarginParam memory, uint256) {
        InternalWithdrawMarginParam memory withdrawParam;

        // if settleOrderParams.maker is one of whitelistedMakers -> settle with pools
        // settleOrderParams.makerData depends on which whitelistedMaker it is
        // makerData is usually retrieved from our backend service: maker-router
        if (context.config.isWhitelistedMaker(settleOrderParams.signedOrder.order.marketId, settleOrderParams.maker)) {
            return (settleOrderParams.makerData, withdrawParam, 0);
        }

        // if settleOrderParams.maker is makerOrder.owner -> settle with another limit order
        // settleOrderParams.makerData is the entire makerOrder
        Order memory takerOrder = settleOrderParams.signedOrder.order;
        Order memory makerOrder = verifyOrderSignature(abi.decode(settleOrderParams.makerData, (SignedOrder)));
        _verifyOrder(context.vault, makerOrder, settleOrderParams.fillAmount);
        _verifyBothOrders(takerOrder, makerOrder);
        _transferFundToMargin(context.vault, makerOrder);
        _getOrderGatewayV2Storage().totalFilledAmount[makerOrder.getKey()] += settleOrderParams.fillAmount;

        // Maker order's maker is himself
        _emitOrderFilled(makerOrder, makerOrder.owner, settleOrderParams.fillAmount, makerOrder.price);

        if (makerOrder.action == ActionType.ReduceOnly) {
            withdrawParam.trader = makerOrder.owner;
            withdrawParam.requiredMarginRatio = FixedPointMathLib
                .max(context.vault.getMarginRatio(takerOrder.marketId, makerOrder.owner, context.oraclePrice), 0)
                .toUint256();
        }

        return (
            abi.encode(
                IClearingHouse.MakerOrder({
                    amount: FixedPointMathLib.fullMulDiv(makerOrder.price, settleOrderParams.fillAmount, WAD)
                })
            ),
            withdrawParam,
            _takeRelayFee(makerOrder)
        );
    }

    struct InternalOpenPositionParams {
        IClearingHouse clearingHouse;
        SettleOrderParam settleOrderParam;
        bytes makerData;
        uint256 takerRelayFee;
        uint256 makerRelayFee;
    }

    function _openPosition(InternalOpenPositionParams memory params) internal {
        Order memory takerOrder = params.settleOrderParam.signedOrder.order;
        bool isBaseToQuote = takerOrder.amount < 0;

        (int256 base, int256 quote) = params.clearingHouse.openPositionFor(
            IClearingHouse.OpenPositionForParams({
                marketId: takerOrder.marketId,
                maker: params.settleOrderParam.maker,
                isBaseToQuote: isBaseToQuote,
                isExactInput: isBaseToQuote,
                amount: params.settleOrderParam.fillAmount,
                oppositeAmountBound: FixedPointMathLib.fullMulDiv(
                    takerOrder.price,
                    params.settleOrderParam.fillAmount,
                    WAD
                ),
                deadline: takerOrder.expiry,
                makerData: params.makerData,
                taker: takerOrder.owner,
                takerRelayFee: params.takerRelayFee,
                makerRelayFee: params.makerRelayFee
            })
        );

        // may not need this guardian
        if (base.abs() != params.settleOrderParam.fillAmount) {
            revert LibError.FilledAmountMismatched(
                takerOrder.owner,
                takerOrder.id,
                params.settleOrderParam.fillAmount,
                base.abs()
            );
        }

        // calculate taker filled price
        _emitOrderFilled(
            takerOrder,
            params.settleOrderParam.maker,
            params.settleOrderParam.fillAmount,
            FixedPointMathLib.fullMulDiv(quote.abs(), WAD, base.abs())
        );
    }

    function _emitOrderFilled(Order memory order, address maker, uint256 fillAmount, uint256 fillPrice) internal {
        emit OrderFilled(
            order.owner,
            order.id,
            order.action,
            order.tradeType,
            order.marketId,
            order.amount,
            fillAmount,
            order.price,
            fillPrice,
            order.expiry,
            order.marginXCD,
            order.relayFee,
            maker
        );
    }

    function _withdrawMargin(
        InternalContext memory context,
        uint256 marketId,
        address trader,
        uint256 requiredMarginRatio
    ) internal {
        uint256 withdrawableMargin = _getWithdrawableMargin(context, marketId, trader, requiredMarginRatio);
        if (withdrawableMargin > 0) {
            context.vault.transferMarginToFund(
                marketId,
                trader,
                withdrawableMargin.formatDecimals(INTERNAL_DECIMALS, context.collateralTokenDecimals)
            );
        }
    }

    //
    // INTERNAL VIEW
    //

    function _verifyOrder(IVault vault, Order memory order, uint256 fillAmount) internal view {
        if (block.timestamp > order.expiry) {
            revert LibError.OrderHasExpired(order.owner, order.id);
        }

        if (isOrderCanceled(order.owner, order.id)) {
            revert LibError.OrderWasCanceled(order.owner, order.id);
        }

        if (order.amount == 0) {
            revert LibError.OrderAmountZero(order.owner, order.id);
        }

        uint256 openAmount = order.amount.abs();

        if (order.tradeType == TradeType.FoK && fillAmount != openAmount) {
            revert LibError.UnableToFillFok(order.owner, order.id);
        }

        uint256 totalFilledAmount = getOrderFilledAmount(order.owner, order.id);
        if (fillAmount > openAmount - totalFilledAmount) {
            revert LibError.ExceedOrderAmount(order.owner, order.id, totalFilledAmount);
        }

        if (order.action == ActionType.ReduceOnly) {
            int256 ownerPositionSize = vault.getPositionSize(order.marketId, order.owner);

            if (order.amount * ownerPositionSize > 0) {
                revert LibError.ReduceOnlySideMismatch(order.owner, order.id, order.amount, ownerPositionSize);
            }

            if (openAmount > ownerPositionSize.abs()) {
                revert LibError.UnableToReduceOnly(order.owner, order.id, openAmount, ownerPositionSize.abs());
            }
        }
    }

    function _verifyBothOrders(Order memory takerOrder, Order memory makerOrder) internal pure {
        if (takerOrder.marketId != makerOrder.marketId) {
            revert LibError.OrderMarketMismatched(
                takerOrder.owner,
                takerOrder.id,
                takerOrder.marketId,
                makerOrder.owner,
                makerOrder.id,
                makerOrder.marketId
            );
        }

        if (takerOrder.amount * makerOrder.amount >= 0) {
            revert LibError.OrderSideMismatched(takerOrder.owner, takerOrder.id, makerOrder.owner, makerOrder.id);
        }
    }

    function _getAsset(IVault vault) internal view returns (address) {
        return vault.getCollateralToken();
    }

    /// @dev get withdrawable margin after reduce position to keep same leverage
    /// @notice the amount is in INTERNAL_DECIMALS
    function _getWithdrawableMargin(
        InternalContext memory context,
        uint256 marketId,
        address trader,
        uint256 requiredMarginRatio
    ) internal view returns (uint256 amount) {
        int256 positionSize = context.vault.getPositionSize(marketId, trader);
        uint256 freeCollateral = context.vault.getFreeCollateral(marketId, trader, context.oraclePrice);
        if (positionSize == 0) {
            return freeCollateral;
        }

        int256 marginRatio = context.vault.getMarginRatio(marketId, trader, context.oraclePrice);
        if (marginRatio < context.imRatio.toInt256() || marginRatio <= requiredMarginRatio.toInt256()) {
            return 0;
        }

        int256 openNotional = context.vault.getOpenNotional(marketId, trader);
        uint256 requiredAccountValue = FixedPointMathLib.fullMulDiv(requiredMarginRatio, openNotional.abs(), WAD);
        int256 accountValue = context.vault.getAccountValue(marketId, trader, context.oraclePrice);
        if (accountValue <= requiredAccountValue.toInt256()) {
            return 0;
        }

        int256 tryToWithdraw = accountValue - requiredAccountValue.toInt256();
        return FixedPointMathLib.min(tryToWithdraw.toUint256(), freeCollateral);
    }

    function _getPrice(
        IPythOracleAdapter pythOracleAdapter,
        Config config,
        uint256 marketId
    ) internal view returns (uint256) {
        (uint256 price, ) = pythOracleAdapter.getPrice(config.getPriceFeedId(marketId));
        return price;
    }

    //
    // PRIVATE
    //

    function _getOrderGatewayV2Storage() private pure returns (OrderGatewayV2Storage storage $) {
        assembly {
            $.slot := _ORDER_GATEWAY_V2_STORAGE_LOCATION
        }
    }
}
