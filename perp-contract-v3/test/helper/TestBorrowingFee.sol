// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../../src/borrowingFee/BorrowingFeeStruct.sol";
import "../../src/borrowingFee/BorrowingFee.sol";

// TODO delete and migrate to latest struct
/// @dev managing the calculations that require both UtilizationGlobal and Utilization
library LibUtilization {
    struct State {
        LibUtilizationGlobal.Info longGlobal;
        LibUtilizationGlobal.Info shortGlobal;
        // key: receiver
        mapping(address => Info) longMadeBy;
        // key: receiver
        mapping(address => Info) shortMadeBy;
    }

    /// @param payerIncreasedSize how much position size receiver made for payer. won't be net out if diff payer increase
    /// long/short from the same receiver. when payer reduce position from a receiver, payerIncreasedSize decreased. this
    /// can be negative.
    /// @param utilRatioFactor utilRatioFactor = utilRatio (reported from receiver) * madeByReceiver.payerIncreasedSize
    struct Info {
        int256 payerIncreasedSize;
        uint256 utilRatioFactor;
    }
}

library LibUtilizationGlobal {
    /// @param totalOpenNotional sum of payer's openNotional trade against with receiver. for calculating borrowing fee.
    /// @param utilRatio liquidity utilization ratio. for calculating borrowing fee.
    struct Info {
        uint256 totalReceiverOpenNotional;
        uint256 totalOpenNotional;
        uint256 utilRatio;
    }
}

contract TestBorrowingFee is BorrowingFee {
    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    /// @return long, short
    function getUtilizationGlobal(
        uint256 marketId
    ) external view returns (LibUtilizationGlobal.Info memory, LibUtilizationGlobal.Info memory) {
        (uint256 longSize, uint256 shortSize) = _getTotalReceiverOpenNotional(marketId);
        (uint256 longOpenNotional, uint256 shortOpenNotional) = _getTotalPayerOpenNotional(marketId);
        (uint256 longUtilRatio, uint256 shortUtilRatio) = _getUtilRatio(marketId);
        return (
            LibUtilizationGlobal.Info({
                totalReceiverOpenNotional: longSize,
                totalOpenNotional: longOpenNotional,
                utilRatio: longUtilRatio
            }),
            LibUtilizationGlobal.Info({
                totalReceiverOpenNotional: shortSize,
                totalOpenNotional: shortOpenNotional,
                utilRatio: shortUtilRatio
            })
        );
    }

    /// @return long, short
    function getPayerFeeGrowth(uint256 marketId, address payer) external view returns (uint256, uint256) {
        return _getPayerFeeGrowth(marketId, payer);
    }

    /// @return long, short
    function getPayerFeeGrowthGlobal(uint256 marketId) external view returns (uint256, uint256) {
        return _getPayerFeeGrowthGlobal(marketId);
    }
}
