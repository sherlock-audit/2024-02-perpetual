// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

library LibError {
    //
    // Common
    //
    error Unauthorized(); // this is for general unauthorized error
    error AuthorizerNotAllow(address authorizer, address authorized); // this is for AuthorizationUpgradeable error
    error InvalidRatio(uint256 ratio);
    error InvalidMaker(uint256 marketId, address maker);
    error InvalidSender(address sender);
    error ZeroAmount();
    error NotEnoughFreeCollateral(uint256 marketId, address trader);
    error NotWhitelistedAuthorization();
    error MismatchedTransferAmount(uint256 actual, uint256 target);
    error ZeroAddress();
    error WrongTransferAmount(uint256 actual, uint256 target);
    error MinMarginRatioExceeded(int256 marinRatio, int256 minMarginRatio);

    //
    // BorrowingFee
    //
    error InvalidPosition();
    error InvalidTaker(address taker);

    //
    // Config
    //
    error MarketExists(uint256 marketId);
    error MakerExists(uint256 marketId, address maker);
    error MakerHasPosition(uint256 marketId, address maker, int256 posSize);
    error ZeroRatio();

    //
    // CircuitBreaker
    //
    error NotAProtectedContract();
    error NotAdmin();
    error InvalidAdminAddress();
    error NoLockedFunds();
    error RateLimited();
    error NotRateLimited();
    error TokenNotRateLimited();
    error CooldownPeriodNotReached();
    error NativeTransferFailed();
    error InvalidRecipientAddress();
    error InvalidGracePeriodEnd();
    error ProtocolWasExploited();
    error NotExploited();

    //
    // ClearingHouse
    //
    error DeadlineExceeded();
    error InsufficientOutputAmount(uint256 actual, uint256 target);
    error ExcessiveInputAmount(uint256 actual, uint256 target);
    error NotLiquidatable(uint256 marketId, address trader);
    error ExcessiveLiquidationPositionSize(
        uint256 marketId,
        address trader,
        uint256 liquidationPositionSize,
        uint256 positionSize
    );
    error CannotLiquidateWhitelistedMaker();
    error QuoteResult(int256 base, int256 quote);
    error NotInstantMaker();
    error InvalidMakerData();
    error ExcessiveRelayFee(address trader, address relayer, uint256 relayFee, uint256 maxRelayFee);
    error PriceOutOfBound(uint256 tradePrice, uint256 lowerPrice, uint256 upperPrice);

    //
    // OrderGateway
    //
    error OrderNotExisted(uint256 orderId);
    error OrderExecutedTooEarly();
    error InvalidOrderType();
    error InvalidDeadline(uint256 deadline);
    error InvalidWithdrawalRatio();

    //
    // OrderGatewayV2
    //
    error ExceedOrderAmount(address owner, bytes32 orderId, uint256 totalFilledAmount);
    error OrderMarketMismatched(
        address takerOrderOwner,
        bytes32 takerOrderId,
        uint256 takerMarketId,
        address makerOrderOwner,
        bytes32 makerOrderId,
        uint256 makerMarketId
    );
    error FilledAmountMismatched(
        address owner,
        bytes32 orderId,
        uint256 orderFilledAmount,
        uint256 clearingHouseFilledAmount
    );
    error OrderHasExpired(address owner, bytes32 orderId);
    error OrderSideMismatched(
        address takerOrderOwner,
        bytes32 takerOrderId,
        address makerOrderOwner,
        bytes32 makerOrderId
    );
    error UnableToFillFok(address owner, bytes32 orderId);
    error SettleOrderParamsLengthError(); // only support length 1 for now
    error OrderSignatureOwnerError(address owner, bytes32 orderId, bytes reason);
    error OrderWasCanceled(address owner, bytes32 orderId);
    error ReduceOnlySideMismatch(address owner, bytes32 orderId, int256 orderAmount, int256 takerPositionSize);
    error UnableToReduceOnly(address owner, bytes32 orderId, uint256 orderAmountAbs, uint256 takerPositionSizeAbs);
    error OrderAmountZero(address owner, bytes32 orderId);

    //
    // SystemStatus
    //
    error SystemIsSuspended();
    error MarketIsSuspended(uint256 marketId);

    //
    // Vault
    //
    error InvalidMarket(uint256 marketId);
    error ZeroTakerPositionSize();
    error DepositCapExceeded();

    //
    // SpotHedgeBaseMaker
    //
    error UnexpectedPerpPrecision(uint8 actual, uint8 expected);
    // Unexpected first token of the given Uniswap V3 path.
    error UnexpectedPathTokenIn(address decodedTokenIn, address expectedTokenIn);
    // Unexpected last token of the given Uniswap V3 path.
    error UnexpectedPathTokenOut(address decodedTokenOut, address expectedTokenOut);
    // The pool specified by the given Uniswap V3 path does not exist (zero address).
    error ZeroPoolAddress(address tokenIn, address tokenOut, uint24 fee);
    // The given swap path (as defined by token in/out) was not set.
    error PathNotSet(address tokenIn, address tokenOut);
    error NotEnoughMargin();
    error NotImplemented(bool isBaseToQuote, bool isExactInput, uint256 amount);
    error NegativeOrZeroVaultValueInBase(int256 vaultValueInBase);
    error NotEnoughSpotBaseTokens(uint256 withdraw, uint256 balance);
    error HasOpenPosition(int256 positionSize);

    //
    // IOracleAdapter
    //
    error OracleDataRequired(bytes32 priceFeedId, bytes reason);
    error OracleFeeRequired(uint feeAmount);
    error IllegalPriceFeed(bytes32 priceFeedId);

    //
    // OracleMaker
    //
    error NegativeOrZeroMargin();
    error InvalidSignedRatio(int256 ratio);
    error NegativeOrZeroVaultValueInQuote(int256 vaultValue);

    //
    // FundModel
    //
    /// @param fund how much fund trader has
    /// @param delta how much delta it want to decrease. must be negative
    error InsufficientFund(address trader, uint256 fund, int256 delta);

    //
    // LibLimiter
    //
    error InvalidMinimumLiquidityThreshold();
    error LimiterAlreadyInitialized();
    error LimiterNotInitialized();

    //
    // PythOracleAdapter
    //
    // Failed to withdraw oracle fee to owner.
    error WithdrawOracleFeeFailed(uint256 amount);
}
