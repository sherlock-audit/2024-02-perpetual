// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { LibMulticaller } from "multicaller/LibMulticaller.sol";

abstract contract ContextBase {
    function _sender() internal view virtual returns (address) {
        return LibMulticaller.sender();
    }
}
