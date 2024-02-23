// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IClearingHouse } from "../clearingHouse/IClearingHouse.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { LibError } from "../common/LibError.sol";

contract Quoter is AddressResolverUpgradeable {
    using LibAddressResolver for IAddressManager;

    error InternalQuoteShouldRevert();

    constructor(address addressManager) initializer {
        __AddressResolver_init(addressManager);
    }

    function quote(IClearingHouse.OpenPositionParams calldata params) external returns (int256, int256) {
        IClearingHouse clearingHouse = getAddressManager().getClearingHouse();

        try clearingHouse.quoteOpenPosition(params) {
            // Just in case because ClearingHouse.quoteOpenPosition() is supposed to revert and
            // the execution should never reach here.
            revert InternalQuoteShouldRevert();
        } catch (bytes memory reason) {
            // ClearingHouse.quoteOpenPosition() is supposed to revert with reason.length >= 32 bytes.
            // If not, propagate the unexpected error.
            uint256 length = reason.length;
            if (length < 32) {
                // Send the original revert data to caller
                assembly {
                    revert(add(reason, 32), length)
                }
            }

            // Note that we can't do "abi.decode(reason, (bytes4))" because it would fail sometimes.
            bytes4 errorSelector = bytes4(abi.decode(reason, (bytes32)));
            bytes memory data;
            assembly {
                data := add(reason, 4)
            }

            if (errorSelector == LibError.QuoteResult.selector) {
                (int256 baseAmount, int256 quoteAmount) = abi.decode(data, (int256, int256));
                return (baseAmount, quoteAmount);
            } else {
                // Send the original revert data to caller
                assembly {
                    revert(add(reason, 32), length)
                }
            }
        }
    }
}
