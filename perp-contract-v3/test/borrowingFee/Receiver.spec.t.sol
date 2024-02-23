// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;
import "./BorrowingFeeSpecSetup.sol";

// TODO
// 1. store in brFee, set from brFee (config is not the only entry anymore)*
// 2. store in brFee, set from Config (brFree affect config when updating interface)*
// 3. store in Config, setFrom brFee (config is not the only entry anymore)
// 4. store in Config, setFrom Config (config includes brFee's logic, assuming it's safe under this condition)
contract ReceiverSpec is BorrowingFeeSpecSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SetReceiver_RevertIf_NotConfig() public {}

    function test_SetReceiver_RevertIf_PositionNotEmpty() public {}

    function test_SetReceiver_RevertIf_TradeStatsNotEmpty() public {}
}
