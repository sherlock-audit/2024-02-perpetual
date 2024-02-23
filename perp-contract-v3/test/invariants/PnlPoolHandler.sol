// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/AbstractPyth.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { ClearingHouse } from "../../src/clearingHouse/ClearingHouse.sol";
import { IClearingHouse } from "../../src/clearingHouse/IClearingHouse.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { LibFormatter } from "../../src/common/LibFormatter.sol";
import { INTERNAL_DECIMALS } from "../../src/common/LibConstant.sol";
import { TestMaker } from "../helper/TestMaker.sol";

contract PnlPoolHandler is StdUtils, StdCheats {
    using EnumerableSet for EnumerableSet.AddressSet;
    using LibFormatter for uint256;

    struct TradeWithWhitelistedMakerParams {
        address taker;
        uint256 collateralAmountXCD;
        address maker;
        uint256 baseToQuotePrice;
        bool isBaseToQuote;
        bool isExactInput;
    }

    Vault public vault;
    ClearingHouse public clearingHouse;
    IERC20Metadata public collateral;
    uint256 public marketId;
    address public pyth;
    bytes32 public priceFeedId;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    EnumerableSet.AddressSet internal makerSet;
    EnumerableSet.AddressSet internal traderSet;
    uint256 public sumInitialMargin;

    constructor(
        Vault vault_,
        ClearingHouse clearingHouse_,
        address pyth_,
        bytes32 priceFeedId_,
        uint256 marketId_,
        address[] memory makerList_
    ) {
        vault = vault_;
        collateral = IERC20Metadata(vault.getCollateralToken());
        clearingHouse = clearingHouse_;
        pyth = pyth_;
        priceFeedId = priceFeedId_;
        marketId = marketId_;
        for (uint256 i = 0; i < makerList_.length; i++) {
            makerSet.add(makerList_[i]);
            traderSet.add(makerList_[i]);
        }
    }

    function tradeWithWhitelistedMaker(
        address taker,
        uint256 collateralAmountXCD,
        uint256 makerIndex,
        int64 price,
        bool isBaseToQuote,
        bool isExactInput
    ) public virtual {
        collateralAmountXCD = bound(collateralAmountXCD, 1e6, 1000000e6);

        TestMaker currentMaker;
        uint256 baseToQuotePrice;

        {
            // random maker
            makerIndex = bound(makerIndex, 0, makerSet.length() - 1);
            currentMaker = TestMaker(makerSet.at(makerIndex));

            // mock oracle price (must simulate a reasonable price fluctuation or otherwise the maker might be bankrupt)
            price = int64(bound(price, 90e8, 110e8));
            int32 priceExpo = -8;

            PythStructs.Price memory basePythPrice = PythStructs.Price(price, 0, priceExpo, block.timestamp);
            vm.mockCall(
                pyth,
                abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId),
                abi.encode(basePythPrice)
            );

            baseToQuotePrice = _convertToUint256(basePythPrice);
            currentMaker.setBaseToQuotePrice(baseToQuotePrice);
        }

        _tradeWithWhitelistedMaker(
            TradeWithWhitelistedMakerParams({
                taker: taker,
                collateralAmountXCD: collateralAmountXCD,
                maker: address(currentMaker),
                baseToQuotePrice: baseToQuotePrice,
                isBaseToQuote: isBaseToQuote,
                isExactInput: isExactInput
            })
        );
    }

    function getTraderSetLength() external returns (uint256) {
        return traderSet.length();
    }

    function getTraderAtIndex(uint256 index) external returns (address) {
        return traderSet.at(index);
    }

    function _tradeWithWhitelistedMaker(TradeWithWhitelistedMakerParams memory params) private {
        _deposit(params.maker, params.collateralAmountXCD);
        _deposit(params.taker, params.collateralAmountXCD);

        vm.startPrank(params.taker);

        // Assume 1x leverage
        uint256 amountQuote = params.collateralAmountXCD.formatDecimals(collateral.decimals(), INTERNAL_DECIMALS);

        uint256 openPositionAmount = ((params.isBaseToQuote && params.isExactInput) ||
            (!params.isBaseToQuote && !params.isExactInput))
            ? FixedPointMathLib.divWad(amountQuote, params.baseToQuotePrice) // base
            : amountQuote; // quote
        clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                marketId: marketId,
                maker: params.maker,
                isBaseToQuote: params.isBaseToQuote,
                isExactInput: params.isExactInput,
                amount: openPositionAmount,
                oppositeAmountBound: (params.isExactInput) ? 0 : type(uint256).max,
                deadline: block.timestamp,
                makerData: ""
            })
        );

        vm.stopPrank();

        // store ghost variables
        traderSet.add(params.taker);
    }

    function _deposit(address trader, uint256 amountXCD) private {
        address collateralAddr = address(collateral);
        deal(collateralAddr, trader, amountXCD, true);
        vm.startPrank(trader);
        if (collateral.allowance(trader, address(vault)) < amountXCD) {
            collateral.approve(address(vault), type(uint256).max);
        }
        vault.deposit(trader, amountXCD);
        vault.transferFundToMargin(marketId, amountXCD);
        vm.stopPrank();

        // Update initial margin sum
        sumInitialMargin += amountXCD.formatDecimals(collateral.decimals(), INTERNAL_DECIMALS);
    }

    // copied from PythOracleAdapter
    function _convertToUint256(PythStructs.Price memory pythPrice) private pure returns (uint256) {
        if (pythPrice.price < 0 || pythPrice.expo > 0 || pythPrice.expo < -int8(INTERNAL_DECIMALS))
            revert("IllegalPrice");
        uint256 baseConversion = 10 ** uint256(int256(int8(INTERNAL_DECIMALS)) + pythPrice.expo);
        return uint256(int256(pythPrice.price)) * baseConversion;
    }
}
