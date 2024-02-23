# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [TBD]

## [0.8.0] - 2024-02-06
- Fix missing `FundChanged` event on `Vault.sol`

## [0.7.2] - 2024-02-05
- Fix `BorrowingFee.sol` calculation rounding issue

## [0.7.1] - 2024-02-02
- Add new error `AuthorizerNotAllow` to `LibError.sol`

## [0.7.0] - 2024-01-31
- reorganize contracts structure
- Move all errors to `LibError.sol`
- Add `CircuitBreaker`
- Add `Authorization` for `ClearingHouse` and `Vault`
- Add `SystemStatus` to pause System or Market


## [0.6.0] - 2024-01-10
- Support withdraw when reduceOnly order in `OrderGatewayV2`
- Replace `LibFullMath` with `prb-math`
- Use solidity 0.8.22 version

## [0.5.0] - 2023-12-29

- Add funding fee
- Add funding account to `Vault`
- Modify deposit & withdraw process
- Rename Sequencer to Matcher

## [0.4.0] - 2023-12-12

- Add `freeCollateralForReduce` to `MarginProfile`
- Fix margin-check edge cases on reducing/closing positions for both taker and maker
- Add `OrderGatewayV2`
- Add `P2pMaker`

## [0.3.0] - 2023-11-21

- Rename `Exchange` to `ClearingHouse`
- Move configuration into `Config` contract
- Rename `Vault.getAccount()` to `Vault.getPosition()`
- Rename `Exchange.getBalance()` to `ClearingHouse.getMarginProfile()`
- Replace `withdrawRatio` param to `withdraw` in `OrderGateway.createOrder()`
- Rename `account` or `wallet` in event/function params to context-related name e.g. trader, taker
- Rename `keeperFee` to `executionFee`
- Prefix `Lib` for all library
- Fix "panic: arithmetic overflow / underflow" before settle borrowing fee
- Keeper can purge order

## [0.2.0] - 2023-10-30

-   Add `LazyMargin`
-   Add `OracleLiquidationEngine`
-   Rename `DelayedOrderGateway` to `OrderGateway`
-   Fix underflow in `updateMakerStatsForReducingPosition` when opening a position
-   Add exporting unsigned multisig txs as JSON

## [0.1.1] - 2023-10-13

-   Support instant order in DelayedOrderGateway

## [0.1.0] - 2023-10-03

-   Add oracle abstraction

## [0.0.15] - 2023-09-18

-   Add keeper fee to `DelayedOrderGateway`

## [0.0.14] - 2023-09-13

-   Add spreads to `PythOracleMaker`
-   Add `IMaker.getAsset()` and `IMaker.getTotalAsset()` for monitoring use
-   Update to node v20

## [0.0.13] - 2023-08-31

-   Rename `Exchange.Account` to `Exchange.Balance`
-   Merge `getMarginRatio` in `Exchange` to `getBalance`

## [0.0.12] - 2023-08-28

-   Add uploading S3 metadata
-   Update and disable maker de-registration
-   Fix system-test script delayed order handling

## [0.0.11] - 2023-08-24

-   `Exchange.openPosition()` is for instant maker only
    -   Starting from this release, `PythOracleMaker` must go through `DelayedOrderGateway`
-   Fix `SpotHedgeBaseMaker.getUtilRatio()`
