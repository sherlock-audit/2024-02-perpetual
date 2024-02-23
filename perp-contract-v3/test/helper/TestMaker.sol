// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { IMaker } from "../../src/maker/IMaker.sol";

contract TestMaker is IMaker {
    using FixedPointMathLib for int256;

    uint256 public marketId;
    uint256 public baseToQuotePrice;
    uint256 public orderDelaySeconds;

    int256 public minMarginRatio = 1 ether; // for FundingFee.getCurrentFundingRate()
    mapping(address => bool) internal _invalidSenderMap;

    Vault public immutable vault;

    constructor(Vault _vault) {
        vault = _vault;
    }

    function setMarketId(uint256 value) external {
        marketId = value;
    }

    function setBaseToQuotePrice(uint256 price) external {
        baseToQuotePrice = price;
    }

    function setMinMarginRatio(int256 value) external {
        minMarginRatio = value;
    }

    function fillOrderCallback(bytes calldata _data) external {
        // No-op
    }

    function fillOrder(
        bool isBaseToQuote,
        bool isExactInput,
        uint256 amount,
        bytes calldata
    ) external view returns (uint256 oppositeAmount, bytes memory callbackData) {
        if ((isBaseToQuote && isExactInput) || (!isBaseToQuote && !isExactInput)) {
            return ((amount * baseToQuotePrice) / 1e18, new bytes(0));
        } else {
            return ((amount * 1e18) / baseToQuotePrice, new bytes(0));
        }
    }

    // MakerUtilReporter will use the default ratio (openNotionalAbs/margin) if it's more than that
    function getUtilRatio() external pure returns (uint256, uint256) {
        return (1e18, 1e18);
    }

    // everyone is valid by default, but open for test to make sender invalid
    function isValidSender(address sender) external view override returns (bool) {
        if (_invalidSenderMap[sender]) return false;
        return true;
    }

    function setInvalidSender(address user, bool isInvalid) public {
        _invalidSenderMap[user] = isInvalid;
    }

    // Not in use
    function getAsset() external pure returns (address) {
        return address(0);
    }

    // Not in use
    function getTotalAssets(uint256) external pure returns (int256) {
        return 0;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }
}
