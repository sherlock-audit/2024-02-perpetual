// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { WAD } from "../common/LibConstant.sol";
import { IVault } from "../vault/IVault.sol";
import { IMaker } from "../maker/IMaker.sol";
import { IMakerReporter } from "./IMakerReporter.sol";

contract MakerReporter is AddressResolverUpgradeable, IMakerReporter {
    using LibAddressResolver for IAddressManager;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address addressManager) external initializer {
        __AddressResolver_init(addressManager);
    }

    /// @notice For calculating borrowing fee. However, maker has incentive to return util ratio as high as possible in
    /// order to maximize the borrowing fee they receive. To mitigate this, borrowing fee should not call maker directly
    /// Instead, it should call MakerReporter to ensure the util ratio is always lower than the the default formula.
    /// @dev util ratio factor = util ratio * position size
    /// util ratio = min(default util ratio, maker reported util ratio)
    /// default util ratio = open notional / margin
    /// @return (longUtilRatio, shortUtilRatio)
    /// TODO adding a <= imRatio risk param to util ratio
    function getUtilRatioFactor(uint256 marketId, address receiver) external view returns (uint256, uint256) {
        IVault vault = getAddressManager().getVault();
        int256 margin = vault.getMargin(marketId, receiver);
        int256 openNotional = vault.getOpenNotional(marketId, receiver);
        uint256 defaultUtilRatio;
        if (margin <= 0) {
            defaultUtilRatio = WAD;
        } else {
            // margin > 0, can type to uint directly
            uint256 positiveMargin = uint256(margin);
            defaultUtilRatio = FixedPointMathLib.min(WAD, openNotional.abs().divWad(positiveMargin));
        }

        uint256 openNotionalAbs = openNotional.abs();
        uint256 defaultUtilRatioFactor = defaultUtilRatio * openNotionalAbs;

        if (openNotional < 0) {
            return (0, defaultUtilRatioFactor);
        }
        return (defaultUtilRatioFactor, 0);

        // TODO: use IMaker().getUtilRatio() when we figure out the solution of SHBM
        //        (uint256 longUtilRatioFromMaker, uint256 shortUtilRatioFromMaker) = IMaker(receiver).getUtilRatio();
        //        //         receiver hold long -> counter party of payer's short -> short rate
        //        if (openNotional < 0) {
        //            return (0, FixedPointMathLib.min(defaultUtilRatioFactor, shortUtilRatioFromMaker * openNotionalAbs));
        //        }
        //        return (FixedPointMathLib.min(defaultUtilRatioFactor, longUtilRatioFromMaker * openNotionalAbs), 0);
    }
}
