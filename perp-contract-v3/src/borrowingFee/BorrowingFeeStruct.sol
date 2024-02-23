// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

/// @param maxBorrowingFeeRate borrowing fee per second per usd notional payer pays when receiver's util ratio is 100%
/// @param utilRatio liquidity utilization ratio. for calculating borrowing fee.
/// @param totalPayerOpenNotional sum of abs(payer's openNotional) trade against with receiver. for calculating borrowing fee
/// @param totalReceiverOpenNotional sum of abs(receiver's open notional). for calculating global ratio's
/// weight between different receivers.
/// @param payerFeeGrowthMap key by payer. fee growth per unit of openNotional as of the last update to position
/// @param receiverFeeGrowthMap key by receiver. fee growth per unit of payerIncreasedSize as of the last update to
/// position or margin. total fee is the same across payer and receiver, but the way to calculate feeGrowth is different
/// @param utilRatioFactorMap key by receiver. utilRatioFactor = utilRatio * receiver's open notional
struct BorrowingFeeState {
    uint256 maxBorrowingFeeRate;
    uint256 utilRatio;
    uint256 totalPayerOpenNotional;
    uint256 totalReceiverOpenNotional;
    FeeGrowthGlobal feeGrowthGlobal;
    mapping(address => uint256) payerFeeGrowthMap;
    mapping(address => uint256) receiverFeeGrowthMap;
    mapping(address => uint256) utilRatioFactorMap;
    // temporary variables for calculating utilRatio
    uint256 lastTotalReceiverOpenNotional;
}

struct FeeGrowthGlobal {
    uint256 payer;
    uint256 receiver;
    uint256 lastUpdated;
}
