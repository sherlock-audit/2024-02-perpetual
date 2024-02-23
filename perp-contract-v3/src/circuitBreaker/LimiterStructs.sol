// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

// Copied from https://github.com/DeFi-Circuit-Breaker/EIPs/tree/master/assets/eip-7265
struct LiqChangeNode {
    uint256 nextTimestamp;
    int256 amount;
}

struct Limiter {
    uint256 minLiqRetainedBps;
    uint256 limitBeginThreshold;
    int256 liqTotal;
    int256 liqInPeriod;
    uint256 listHead;
    uint256 listTail;
    mapping(uint256 => LiqChangeNode) listNodes;
}
