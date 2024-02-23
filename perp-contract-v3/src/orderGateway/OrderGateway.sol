// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

// solhint-disable-next-line max-line-length
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { LibEnumerableSetValues } from "./LibEnumerableSetValues.sol";
import { ClearingHouse } from "../clearingHouse/ClearingHouse.sol";
import { IClearingHouse } from "../clearingHouse/IClearingHouse.sol";
import { Config } from "../config/Config.sol";
import { LibError } from "../common/LibError.sol";
import { IMaker } from "../maker/IMaker.sol";
import { ContextBase } from "../common/ContextBase.sol";

// TODO: rename to DelayedOrderGateway since all orders are delayed
// All orders are 2-step (even for makers that don't require delayed, ex: SpotHedgeBaseMaker):
// 1. Create the order
// 2. After 3 seconds, execute the order
//   - The delay second is configurable via Config.setOrderDelaySeconds()
contract OrderGateway is ContextBase, AddressResolverUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.UintSet;
    using LibEnumerableSetValues for EnumerableSet.UintSet;
    using LibAddressResolver for IAddressManager;
    using SafeCast for uint256;
    using FixedPointMathLib for int256;

    enum DelayedOrderType {
        OpenPosition,
        ClosePosition
    }

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.orderGateway
    struct OrderGatewayStorage {
        uint256 nonce;
        // global order id set
        EnumerableSet.UintSet orderIds;
        // key: taker, value: taker's order id set
        mapping(address => EnumerableSet.UintSet) userOrderIdsMap;
        // key: order id, value: delayed order
        mapping(uint256 => DelayedOrder) ordersMap;
    }

    struct DelayedOrder {
        DelayedOrderType orderType;
        address sender;
        uint256 marketId;
        uint256 createdAt;
        uint256 executableAt;
        bytes data;
    }

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.orderGateway")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _ORDER_GATEWAY_STORAGE_LOCATION =
        0xdf100d1908f02ab5e3e080e35bd0cae71513ed55f143c022ffe0bd974e0bdd00;

    event OrderCreated(uint256 indexed orderId, address indexed sender, uint256 indexed marketId, bytes orderData);
    event OrderExecuted(
        uint256 indexed orderId,
        address indexed sender,
        uint256 indexed marketId,
        address keeper,
        bytes orderData
    );
    event OrderPurged(
        uint256 indexed orderId,
        address indexed sender,
        uint256 indexed marketId,
        address keeper,
        bytes orderData,
        bytes reason
    );
    event OrderCanceled(uint256 indexed orderId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) external initializer {
        __AddressResolver_init(addressManager);
        __ReentrancyGuard_init();
    }

    //
    // EXTERNAL NON VIEW
    //

    function createOrder(DelayedOrderType orderType, bytes calldata data) external nonReentrant {
        bytes memory makerData;
        uint256 marketId;

        Config config = getAddressManager().getConfig();

        uint256 deadline;
        address maker;
        if (orderType == DelayedOrderType.OpenPosition) {
            IClearingHouse.OpenPositionParams memory params = abi.decode(data, (IClearingHouse.OpenPositionParams));
            marketId = params.marketId;
            maker = params.maker;
            makerData = params.makerData;
            deadline = params.deadline;
        } else if (orderType == DelayedOrderType.ClosePosition) {
            IClearingHouse.ClosePositionParams memory params = abi.decode(data, (IClearingHouse.ClosePositionParams));
            marketId = params.marketId;
            maker = params.maker;
            makerData = params.makerData;
            deadline = params.deadline;
        } else {
            revert LibError.InvalidOrderType();
        }

        if (!config.isWhitelistedMaker(marketId, maker)) {
            revert LibError.InvalidMaker(marketId, maker);
        }

        uint256 orderDelaySeconds = config.getOrderDelaySeconds();
        if (
            deadline == 0 ||
            deadline > block.timestamp + config.getMaxOrderValidDuration() ||
            deadline < block.timestamp + orderDelaySeconds
        ) {
            revert LibError.InvalidDeadline(deadline);
        }

        DelayedOrder memory delayedOrder = DelayedOrder({
            orderType: orderType,
            sender: _sender(),
            marketId: marketId,
            createdAt: block.timestamp,
            executableAt: block.timestamp + orderDelaySeconds,
            data: data
        });

        uint256 orderId = _addOrder(delayedOrder);
        emit OrderCreated(orderId, delayedOrder.sender, marketId, abi.encode(delayedOrder));
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        address sender = _sender();
        if (!_getOrderGatewayStorage().userOrderIdsMap[sender].contains(orderId)) {
            revert LibError.OrderNotExisted(orderId);
        }

        DelayedOrder memory delayedOrder = _getOrderGatewayStorage().ordersMap[orderId];
        _removeOrder(orderId);

        emit OrderCanceled(orderId);
    }

    function executeOrder(
        uint256 orderId,
        bytes calldata makerData
    ) external nonReentrant returns (int256 base, int256 quote) {
        DelayedOrder memory delayedOrder = _getOrderGatewayStorage().ordersMap[orderId];

        IAddressManager addressManager = getAddressManager();
        (, uint256 priceTimestamp) = addressManager.getPythOracleAdapter().getPrice(
            addressManager.getConfig().getPriceFeedId(delayedOrder.marketId)
        );

        if (priceTimestamp < delayedOrder.executableAt) {
            revert LibError.OrderExecutedTooEarly();
        }

        bytes memory errorReason;
        (base, quote, errorReason) = _tryExecuteOrder(delayedOrder, makerData);

        _removeOrder(orderId);

        address keeper = _sender();

        if (errorReason.length != 0) {
            emit OrderPurged(
                orderId,
                delayedOrder.sender,
                delayedOrder.marketId,
                keeper,
                abi.encode(delayedOrder),
                errorReason
            );
        } else {
            emit OrderExecuted(orderId, delayedOrder.sender, delayedOrder.marketId, keeper, abi.encode(delayedOrder));
        }

        return (base, quote);
    }

    /// @dev external function called by itself for try catch
    function executeOrderBySelf(
        DelayedOrder memory delayedOrder,
        bytes memory makerData
    ) external returns (int256 base, int256 quote) {
        if (msg.sender != address(this)) {
            revert LibError.InvalidSender(msg.sender);
        }
        return _executeOrder(delayedOrder, makerData);
    }

    //
    // PUBLIC VIEW
    //
    function getCurrentNonce() public view returns (uint256) {
        return _getOrderGatewayStorage().nonce;
    }

    function getOrdersCount() public view returns (uint256) {
        return _getOrderGatewayStorage().orderIds.length();
    }

    function getOrderIds(uint256 start, uint256 end) public view returns (uint256[] memory) {
        return _getOrderGatewayStorage().orderIds.valuesAt(start, end);
    }

    function getUserOrdersCount(address taker) public view returns (uint256) {
        return _getOrderGatewayStorage().userOrderIdsMap[taker].length();
    }

    function getUserOrderIds(address taker, uint256 start, uint256 end) public view returns (uint256[] memory) {
        return _getOrderGatewayStorage().userOrderIdsMap[taker].valuesAt(start, end);
    }

    function getOrder(uint256 orderId) public view returns (DelayedOrder memory) {
        return _getOrderGatewayStorage().ordersMap[orderId];
    }

    //
    // INTERNAL NON VIEW
    //

    function _addOrder(DelayedOrder memory delayedOrder) internal returns (uint256) {
        uint256 orderId = getCurrentNonce();
        _getOrderGatewayStorage().orderIds.add(orderId);
        _getOrderGatewayStorage().userOrderIdsMap[delayedOrder.sender].add(orderId);
        _getOrderGatewayStorage().ordersMap[orderId] = delayedOrder;
        _increaseNonce();
        return orderId;
    }

    function _executeOrder(
        DelayedOrder memory delayedOrder,
        bytes memory makerData
    ) internal returns (int256 base, int256 quote) {
        IClearingHouse clearingHouse = getAddressManager().getClearingHouse();

        if (delayedOrder.orderType == DelayedOrderType.OpenPosition) {
            IClearingHouse.OpenPositionParams memory params = abi.decode(
                delayedOrder.data,
                (IClearingHouse.OpenPositionParams)
            );
            (base, quote) = clearingHouse.openPositionFor(
                IClearingHouse.OpenPositionForParams({
                    marketId: params.marketId,
                    maker: params.maker,
                    isBaseToQuote: params.isBaseToQuote,
                    isExactInput: params.isExactInput,
                    amount: params.amount,
                    oppositeAmountBound: params.oppositeAmountBound,
                    deadline: params.deadline,
                    makerData: makerData, // relayer has to specify the makerData when executing the order
                    taker: delayedOrder.sender,
                    takerRelayFee: 0,
                    makerRelayFee: 0
                })
            );
        } else if (delayedOrder.orderType == DelayedOrderType.ClosePosition) {
            IClearingHouse.ClosePositionParams memory params = abi.decode(
                delayedOrder.data,
                (IClearingHouse.ClosePositionParams)
            );
            (base, quote) = clearingHouse.closePositionFor(
                IClearingHouse.ClosePositionForParams({
                    marketId: params.marketId,
                    maker: params.maker,
                    oppositeAmountBound: params.oppositeAmountBound,
                    deadline: params.deadline,
                    makerData: makerData, // relayer has to specify the makerData when executing the order
                    taker: delayedOrder.sender,
                    takerRelayFee: 0,
                    makerRelayFee: 0
                })
            );
        } else {
            revert LibError.InvalidOrderType();
        }
        return (base, quote);
    }

    function _tryExecuteOrder(
        DelayedOrder memory delayedOrder,
        bytes memory makerData
    ) internal returns (int256, int256, bytes memory) {
        try this.executeOrderBySelf(delayedOrder, makerData) returns (int256 base, int256 quote) {
            return (base, quote, hex"");
        } catch Error(string memory errorReason) {
            revert(errorReason);
        } catch (bytes memory errorReason) {
            bytes4 errorSelector = _getErrorSelector(errorReason);
            uint256 length = errorReason.length;
            if (
                errorSelector == LibError.InvalidOrderType.selector ||
                errorSelector == LibError.MismatchedTransferAmount.selector ||
                errorSelector == LibError.DeadlineExceeded.selector ||
                errorSelector == LibError.InvalidMaker.selector ||
                errorSelector == LibError.InvalidMakerData.selector ||
                errorSelector == LibError.Unauthorized.selector ||
                errorSelector == LibError.ZeroAmount.selector ||
                errorSelector == LibError.NotEnoughFreeCollateral.selector ||
                errorSelector == LibError.InsufficientOutputAmount.selector ||
                errorSelector == LibError.ExcessiveInputAmount.selector ||
                errorSelector == LibError.AuthorizerNotAllow.selector
            ) {
                return (0, 0, errorReason);
            } else {
                // Send the original revert data to caller
                assembly {
                    revert(add(errorReason, 32), length)
                }
            }
        }
    }

    function _removeOrder(uint256 orderId) internal {
        _getOrderGatewayStorage().orderIds.remove(orderId);
        _getOrderGatewayStorage().userOrderIdsMap[_getOrderGatewayStorage().ordersMap[orderId].sender].remove(orderId);
        delete _getOrderGatewayStorage().ordersMap[orderId];
    }

    function _increaseNonce() internal {
        _getOrderGatewayStorage().nonce++;
    }

    //
    // INTERNAL VIEW
    //

    function _getErrorSelector(bytes memory data) internal pure returns (bytes4) {
        bytes4 errorSelector;
        assembly {
            errorSelector := mload(add(data, 0x20))
        }
        return errorSelector;
    }

    //
    // PRIVATE
    //

    function _getOrderGatewayStorage() private pure returns (OrderGatewayStorage storage $) {
        assembly {
            $.slot := _ORDER_GATEWAY_STORAGE_LOCATION
        }
    }
}
