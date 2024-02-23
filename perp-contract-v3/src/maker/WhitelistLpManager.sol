// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IWhitelistLpManager } from "./IWhitelistLpManager.sol";

/**
 * @title WhitelistLpManager
 */
contract WhitelistLpManager is IWhitelistLpManager, Ownable2Step {
    /*************
     * Variables *
     *************/

    mapping(address => bool) private whitelistLpMap;

    constructor() Ownable(msg.sender) {}

    function setWhitelistLp(address lp, bool isWhitelisted) external onlyOwner {
        bool oldIsWhitelisted = whitelistLpMap[lp];
        whitelistLpMap[lp] = isWhitelisted;
        emit WhitelistLpSet(lp, isWhitelisted, oldIsWhitelisted);
    }

    function isLpWhitelisted(address lp) external view returns (bool) {
        return whitelistLpMap[lp];
    }
}
