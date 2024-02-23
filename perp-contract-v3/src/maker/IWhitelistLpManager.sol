// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IWhitelistLpManager {
    event WhitelistLpSet(address indexed lp, bool newIsWhitelisted, bool oldIsWhitelisted);

    function isLpWhitelisted(address lp) external view returns (bool);
}
