// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { AbstractPyth } from "pyth-sdk-solidity/AbstractPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { IPythOracleAdapter } from "./IPythOracleAdapter.sol";
import { INTERNAL_DECIMALS } from "../../common/LibConstant.sol";
import { LibError } from "../../common/LibError.sol";

contract PythOracleAdapter is IPythOracleAdapter, Ownable2Step {
    IPyth internal _pyth;
    uint256 internal _maxPriceAge;

    /// @notice Price outside of the adapter's acceptance range (ex. negative price, extreme decimals, etc.)
    error IllegalPrice(PythStructs.Price price);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address pyth_) Ownable(msg.sender) {
        _pyth = IPyth(pyth_);
        _setMaxPriceAge(60);
    }

    function depositOracleFee() external payable {
        emit OracleFeeDeposited(_msgSender(), msg.value);
    }

    function withdrawOracleFee() external onlyOwner {
        // get the amount of Ether stored in this contract
        uint256 amount = address(this).balance;

        // send all Ether to owner
        (bool success, ) = payable(owner()).call{ value: amount }("");
        if (!success) revert LibError.WithdrawOracleFeeFailed(amount);

        emit OracleFeeWithdrawn(owner(), amount);
    }

    function setMaxPriceAge(uint256 maxPriceAge) external onlyOwner {
        _setMaxPriceAge(maxPriceAge);
    }

    function _setMaxPriceAge(uint256 maxPriceAge) internal {
        uint256 oldMaxPriceAge = _maxPriceAge;
        _maxPriceAge = maxPriceAge;
        emit MaxPriceAgeSet(maxPriceAge, oldMaxPriceAge);
    }

    /// @inheritdoc IPythOracleAdapter
    function updatePrice(bytes32 priceFeedId, bytes memory signedData) external {
        if (!priceFeedExists(priceFeedId)) revert LibError.IllegalPriceFeed(priceFeedId);

        // Assume we always update only one oracle.
        bytes[] memory pythUpdateData = new bytes[](1);
        pythUpdateData[0] = signedData;

        // Get fee amount to pay to Pyth
        uint256 fee = _pyth.getUpdateFee(pythUpdateData);
        uint256 balance = address(this).balance;
        if (balance < fee) revert LibError.OracleFeeRequired(fee);

        _pyth.updatePriceFeeds{ value: fee }(pythUpdateData);
    }

    function getPyth() external view returns (address) {
        return address(_pyth);
    }

    //
    // PUBLIC VIEW
    //

    /// @inheritdoc IPythOracleAdapter
    function priceFeedExists(bytes32 priceFeedId) public view returns (bool) {
        return AbstractPyth(address(_pyth)).priceFeedExists(priceFeedId);
    }

    /// @inheritdoc IPythOracleAdapter
    function getPrice(bytes32 priceFeedId) public view returns (uint256, uint256) {
        // We don't use pyth.getPrice(), so we can control when to revert with _maxPriceAge,
        // reverted with StalePrice if price.publishTime exceeds _maxPriceAge
        try _pyth.getPriceNoOlderThan(priceFeedId, _maxPriceAge) returns (PythStructs.Price memory price) {
            // Assumes base price is against quote
            return (_convertToUint256(price), price.publishTime);
        } catch (bytes memory reason) {
            revert LibError.OracleDataRequired(priceFeedId, reason);
        }
    }

    function getMaxPriceAge() external view returns (uint256) {
        return _maxPriceAge;
    }

    //
    // INTERNAL PURE
    //

    function _convertToUint256(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        // Remember to update the conversion formula below accordingly if you have changed the conditions.
        // Note both calculations below rely on the conditions here to prevent from overflow.
        // Be sure to double check if you change the conditions.
        if (pythPrice.price < 0 || pythPrice.expo > 0 || pythPrice.expo < -int8(INTERNAL_DECIMALS))
            revert IllegalPrice(pythPrice);

        // .price = 181803
        // .expo = -2
        // decimal price = 181803 * 10^(-2) =  1818.03
        // converted price = 181803 * 10^(18 - 2) = 1.81803e21

        uint256 baseConversion = 10 ** uint256(int256(int8(INTERNAL_DECIMALS)) + pythPrice.expo);

        return uint256(int256(pythPrice.price)) * baseConversion;
    }
}
