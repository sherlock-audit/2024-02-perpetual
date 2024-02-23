// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

// used for all internal accounting in the protocol
// will not be updated after deployment
uint8 constant INTERNAL_DECIMALS = 18;

// Used for internal precision and ratio
uint256 constant WAD = 10 ** INTERNAL_DECIMALS;
