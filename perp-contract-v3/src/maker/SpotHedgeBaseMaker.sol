// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// solhint-disable-next-line max-line-length
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
// solhint-disable-next-line max-line-length
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { AddressResolverUpgradeable } from "../addressResolver/AddressResolverUpgradeable.sol";
import { LibAddressResolver } from "../addressResolver/LibAddressResolver.sol";
import { INTERNAL_DECIMALS, WAD } from "../common/LibConstant.sol";
import { IMaker } from "./IMaker.sol";
import { IVault } from "../vault/IVault.sol";
import { IUniswapV3Factory } from "../external/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { ISwapRouter } from "../external/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IQuoter } from "../external/uniswap-v3-periphery/contracts/interfaces/IQuoter.sol";
import { Path } from "../external/uniswap-v3-periphery/contracts/libraries/Path.sol";
import { BytesLib } from "../external/uniswap-v3-periphery/contracts/libraries/BytesLib.sol";
import { LibFormatter } from "../common/LibFormatter.sol";
import { LibError } from "../common/LibError.sol";
import { ContextBase } from "../common/ContextBase.sol";
import { IWhitelistLpManager } from "./IWhitelistLpManager.sol";

contract SpotHedgeBaseMaker is
    ContextBase,
    AddressResolverUpgradeable,
    Ownable2StepUpgradeable,
    ERC20Upgradeable,
    IMaker
{
    using SafeERC20 for IERC20Metadata;
    using BytesLib for bytes;
    using Path for bytes;
    using SafeCast for int256;
    using SafeCast for uint256;
    using LibFormatter for uint256;
    using LibFormatter for int256;
    using FixedPointMathLib for uint256;
    using LibAddressResolver for IAddressManager;

    //
    // STRUCT
    //

    /// @custom:storage-location erc7201:perp.storage.spotHedgeBaseMaker
    struct SpotHedgeBaseMakerStorage {
        uint256 marketId;
        IERC20Metadata baseToken;
        IERC20Metadata quoteToken;
        uint8 baseTokenDecimals;
        uint8 quoteTokenDecimals;
        // UniswapV3 related
        ISwapRouter uniswapV3Router;
        IUniswapV3Factory uniswapV3Factory;
        IQuoter uniswapV3Quoter;
        // Key is a function of (tokenIn, tokenOut).
        // However, note that since Uniswap's SwapRouter.exactOutput() takes path in reversed order,
        // one should switch the key's tokenIn and tokenOut when querying paths for exactOutput calls.
        mapping(bytes32 => bytes) uniswapV3PathMap;
        // Internal ledger
        uint256 baseTokenLiability;
        uint256 minMarginRatio; // Min. marign ratio required by the maker at all time.
    }

    struct UniswapV3ExactInputParams {
        address tokenIn;
        address tokenOut;
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct UniswapV3ExactOutputParams {
        address tokenIn;
        address tokenOut;
        bytes path;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    struct FillOrderCallbackData {
        bool isBaseToQuote;
        bool isExactInput;
        uint256 amountXSpotDecimals;
        uint256 oppositeAmountXSpotDecimals;
    }

    //
    // Event
    //

    event Deposited(
        address depositor,
        uint256 shares, // Amount of share minted
        uint256 underlying // Amount of underlying token deposited
    );

    event Withdrawn(
        address withdrawer,
        uint256 shares, // Amount of shares burnt
        uint256 baseAmount, // Amount of base tokens withdrawn from maker contract
        uint256 quoteAmount // Amount of quote tokens withdrawn from maker's Perp position
    );

    event UniswapV3RouterSet(address newUniswapV3Router, address oldUniswapV3Router);
    event UniswapV3FactorySet(address newUniswapV3Factory, address oldUniswapV3Factory);
    event UniswapV3QuoterSet(address newUniswapV3Quoter, address oldUniswapV3Quoter);

    // solhint-disable-next-line max-line-length
    // Forked from https://github.com/perpetual-protocol/kantaban-contract/blob/18e0c1fe16490ccc9cbf0d9514e2204964f31624/contracts/interface/IRouterEvent.sol#L6-L13
    /**
     * @dev Emitted when UniswapV3 multihop path of tokenIn/tokenOut pair is changed
     * @param tokenIn The address of tokenIn
     * @param tokenOut The address of tokenOut
     * @param oldPath The old UniswapV3 multihop path
     * @param newPath The new UniswapV3 multihop path
     */
    event UniswapV3PathSet(address tokenIn, address tokenOut, bytes newPath, bytes oldPath);

    event MinMarginRatioSet(uint256 newMinMarginRatio, uint256 oldMinMarginRatio);

    event SHMOrderFilled(
        uint256 marketId,
        bytes path,
        bool isBaseToQuote,
        bool isExactInput,
        uint256 targetAmount, // in INTERNAL_DECIMALS
        uint256 oppositeAmount, // in INTERNAL_DECIMALS
        uint256 spread // In percentage (1e6 = 100%)
    );

    //
    // STATE
    //

    // keccak256(abi.encode(uint256(keccak256("perp.storage.spotHedgeBaseMaker")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 constant _SPOT_HEDGE_BASE_MAKER_STORAGE_LOCATION =
        0xaa0ea57ca6018b18cb09d20625ac40a68ba646a22caa4398d37ac2dfe2dc7500;

    //
    // MODIFIER
    //
    modifier onlyClearingHouse() {
        if (msg.sender != address(getAddressManager().getClearingHouse())) revert LibError.Unauthorized();
        _;
    }

    modifier onlyWhitelistLp() {
        IWhitelistLpManager whitelistManager = getAddressManager().getWhitelistLpManager();
        if (address(whitelistManager) != address(0)) {
            if (!whitelistManager.isLpWhitelisted(_sender())) revert LibError.Unauthorized();
        }
        _;
    }

    //
    // EXTERNAL NON-VIEW
    //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 marketId_,
        string memory name_,
        string memory symbol_,
        address addressManager_,
        address uniswapV3Router_,
        address uniswapV3Factory_,
        address uniswapV3Quoter_,
        address baseToken_,
        uint256 minMarginRatio_
    ) external initializer {
        __AddressResolver_init(addressManager_);
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __ERC20_init(name_, symbol_);

        SpotHedgeBaseMakerStorage storage $ = _getSpotHedgeBaseMakerStorage();

        $.marketId = marketId_;

        setUniswapV3Router(uniswapV3Router_);
        setUniswapV3Factory(uniswapV3Factory_);
        setUniswapV3Quoter(uniswapV3Quoter_);

        $.baseToken = IERC20Metadata(baseToken_);
        $.baseTokenDecimals = IERC20Metadata($.baseToken).decimals();
        $.quoteToken = IERC20Metadata(_getVault().getCollateralToken());
        $.quoteTokenDecimals = IERC20Metadata($.quoteToken).decimals();

        setMinMarginRatio(minMarginRatio_);
    }

    function setUniswapV3Router(address _uniswapV3Router) public onlyOwner {
        if (_uniswapV3Router == address(0)) revert LibError.ZeroAddress();

        address oldUniswapV3Router = address(_getSpotHedgeBaseMakerStorage().uniswapV3Router);
        _getSpotHedgeBaseMakerStorage().uniswapV3Router = ISwapRouter(_uniswapV3Router);

        emit UniswapV3RouterSet(_uniswapV3Router, oldUniswapV3Router);
    }

    function setUniswapV3Factory(address _uniswapV3Factory) public onlyOwner {
        if (_uniswapV3Factory == address(0)) revert LibError.ZeroAddress();

        address oldUniswapV3Factory = address(_getSpotHedgeBaseMakerStorage().uniswapV3Factory);
        _getSpotHedgeBaseMakerStorage().uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);

        emit UniswapV3FactorySet(_uniswapV3Factory, oldUniswapV3Factory);
    }

    function setUniswapV3Quoter(address _uniswapV3Quoter) public onlyOwner {
        if (_uniswapV3Quoter == address(0)) revert LibError.ZeroAddress();

        address oldUniswapV3Quoter = address(_getSpotHedgeBaseMakerStorage().uniswapV3Quoter);
        _getSpotHedgeBaseMakerStorage().uniswapV3Quoter = IQuoter(_uniswapV3Quoter);

        emit UniswapV3QuoterSet(_uniswapV3Quoter, oldUniswapV3Quoter);
    }

    // solhint-disable-next-line max-line-length
    // Forked from https://github.com/perpetual-protocol/kantaban-contract/blob/18e0c1fe16490ccc9cbf0d9514e2204964f31624/contracts/Router.sol#L33-L45
    function setUniswapV3Path(address tokenIn, address tokenOut, bytes calldata path) external onlyOwner {
        _verifyPath(tokenIn, tokenOut, path);

        bytes32 key = _getKey(tokenIn, tokenOut);
        bytes memory oldPath = _getSpotHedgeBaseMakerStorage().uniswapV3PathMap[key];
        _getSpotHedgeBaseMakerStorage().uniswapV3PathMap[key] = path;

        emit UniswapV3PathSet(tokenIn, tokenOut, path, oldPath);
    }

    function setMinMarginRatio(uint256 _minMarginRatio) public onlyOwner {
        if (_minMarginRatio > WAD) {
            revert LibError.InvalidRatio(_minMarginRatio);
        }
        if (_minMarginRatio == 0) {
            revert LibError.ZeroRatio();
        }
        uint256 oldMinMarginRatio = _getSpotHedgeBaseMakerStorage().minMarginRatio;
        _getSpotHedgeBaseMakerStorage().minMarginRatio = _minMarginRatio;

        emit MinMarginRatioSet(_minMarginRatio, oldMinMarginRatio);
    }

    function deposit(uint256 amountXBD) external onlyWhitelistLp returns (uint256) {
        address lp = _sender();
        address maker = address(this);

        if (amountXBD == 0) revert LibError.ZeroAmount();

        uint256 shares;
        if (totalSupply() == 0) {
            shares = amountXBD;
        } else {
            // TODO Should consider slippage once maker has spread or other pricing logic.
            // For now, we will just get account value from ClearingHouse (assume no slippages).
            // shares per asset = share (share token precision) / (accountValue (INTERNAL_DECIMALS) / basePrice (pyth precision) + baseBalance (base token precision))
            // shares (share token precision) =  assets (base token precision) * shares per asset

            // TODO: We should add protections to prevent attackers from manipulating the share price by manipulating oracle reported price.
            // This is because the attacker could potentially mint large amount of shares by forcing the share price low.
            // Possible protections like rate limiting share price, or any kind of volatility check.

            uint8 shareDecimals = decimals();
            uint256 vaultValueInBaseXShareDecimals = _getVaultValueInBaseSafe(_getVault(), _getPrice()).formatDecimals(
                INTERNAL_DECIMALS,
                shareDecimals
            );

            shares =
                (amountXBD.formatDecimals(_getSpotHedgeBaseMakerStorage().baseTokenDecimals, shareDecimals) *
                    totalSupply()) /
                vaultValueInBaseXShareDecimals;
        }

        uint256 balanceBefore = _getSpotHedgeBaseMakerStorage().baseToken.balanceOf(maker);
        _getSpotHedgeBaseMakerStorage().baseToken.safeTransferFrom(_sender(), maker, amountXBD);
        uint256 transferredAmount = _getSpotHedgeBaseMakerStorage().baseToken.balanceOf(maker) - balanceBefore;

        if (transferredAmount != amountXBD) {
            revert LibError.WrongTransferAmount(transferredAmount, amountXBD);
        }

        _getSpotHedgeBaseMakerStorage().baseTokenLiability += amountXBD;

        _mint(lp, shares);

        emit Deposited(lp, shares, amountXBD);

        return shares;
    }

    function withdraw(uint256 shares) external onlyWhitelistLp returns (uint256 baseAmount, uint256 quoteAmount) {
        address lp = _sender();
        address maker = address(this);
        IVault vault = _getVault();

        if (shares == 0) revert LibError.ZeroAmount();

        // Must done before burn.
        uint256 redeemedRatio = shares.divWad(totalSupply()); // in ratio decimals 18

        // Revert early if shares amount exceeds balance
        _burn(lp, shares);

        _getSpotHedgeBaseMakerStorage().baseTokenLiability -= _getSpotHedgeBaseMakerStorage().baseTokenLiability.mulWad(
            redeemedRatio
        );

        uint256 price = _getPrice();
        uint256 vaultValueInBase = _getVaultValueInBaseSafe(vault, price);
        uint256 withdrawnBaseAmount = vaultValueInBase.mulWad(redeemedRatio).formatDecimals(
            INTERNAL_DECIMALS,
            _getSpotHedgeBaseMakerStorage().baseTokenDecimals
        );

        uint256 withdrawnQuoteAmount = 0;

        uint256 spotBaseBalance = _getSpotHedgeBaseMakerStorage().baseToken.balanceOf(maker);

        if (withdrawnBaseAmount > spotBaseBalance) {
            if (vault.getPositionSize(_getSpotHedgeBaseMakerStorage().marketId, maker) != 0) {
                revert LibError.NotEnoughSpotBaseTokens(withdrawnBaseAmount, spotBaseBalance);
            } else {
                withdrawnQuoteAmount = (withdrawnBaseAmount - spotBaseBalance).mulWad(price).formatDecimals(
                    _getSpotHedgeBaseMakerStorage().baseTokenDecimals,
                    _getSpotHedgeBaseMakerStorage().quoteTokenDecimals
                );
                withdrawnBaseAmount = FixedPointMathLib.min(withdrawnBaseAmount, spotBaseBalance);
            }
        }

        if (withdrawnBaseAmount > 0) {
            _getSpotHedgeBaseMakerStorage().baseToken.safeTransfer(lp, withdrawnBaseAmount);
        }
        if (withdrawnQuoteAmount > 0) {
            // withdrawnQuoteAmount is calculated base on freeCollateral, and since all conversions are round-down,
            // we can safely assume withdrawnQuoteAmount <= freeCollateral and the withdraw should always pass.
            // It may not be possible to withdraw the required amount, due to unsettledPnl that cannot be settled totally.
            _withdraw(vault, _getSpotHedgeBaseMakerStorage().marketId, withdrawnQuoteAmount);
            _getSpotHedgeBaseMakerStorage().quoteToken.safeTransfer(lp, withdrawnQuoteAmount);
        }

        emit Withdrawn(lp, shares, withdrawnBaseAmount, withdrawnQuoteAmount);

        return (withdrawnBaseAmount, withdrawnQuoteAmount);
    }

    function fillOrderCallback(bytes calldata _data) external onlyClearingHouse {
        FillOrderCallbackData memory data = abi.decode(_data, (FillOrderCallbackData));
        _fillOrderCallback(data);
        _checkMinMarginRatio(_getPrice());
    }

    function fillOrder(
        bool isBaseToQuote,
        bool isExactInput,
        uint256 amount,
        bytes calldata
    ) external onlyClearingHouse returns (uint256, bytes memory) {
        IVault vault = _getVault();
        uint256 _marketId = _getSpotHedgeBaseMakerStorage().marketId;
        address maker = address(this);

        // Taker perp - maker uniswap matrix:
        //
        //                      perp B->Q                   perp Q->B
        // perp exact input     spot B->Q exact input       spot Q->B exact input
        // perp exact output    spot B->Q exact output      spot Q->B exact output

        FillOrderCallbackData memory fillOrderCallbackData = FillOrderCallbackData({
            isBaseToQuote: isBaseToQuote,
            isExactInput: isExactInput,
            amountXSpotDecimals: 0, // TBD
            oppositeAmountXSpotDecimals: 0 // TBD
        });

        uint256 oppositeAmount;
        bytes memory path;
        if (isBaseToQuote) {
            uint256 quoteTokenAcquired = 0;
            path = _getPath(
                address(_getSpotHedgeBaseMakerStorage().baseToken),
                address(_getSpotHedgeBaseMakerStorage().quoteToken),
                isExactInput
            );

            if (isExactInput) {
                uint256 baseTokenRequired = _formatPerpToSpotBaseDecimals(amount);
                quoteTokenAcquired = _uniswapV3ExactInput(
                    UniswapV3ExactInputParams({
                        tokenIn: address(_getSpotHedgeBaseMakerStorage().baseToken),
                        tokenOut: address(_getSpotHedgeBaseMakerStorage().quoteToken),
                        path: path,
                        recipient: maker,
                        amountIn: baseTokenRequired,
                        amountOutMinimum: 0
                    })
                );
                oppositeAmount = _formatSpotToPerpQuoteDecimals(quoteTokenAcquired);
                // Currently we don't utilize fillOrderCallback for B2Q swaps,
                // but we still populate the arguments anyways.
                fillOrderCallbackData.amountXSpotDecimals = baseTokenRequired;
                fillOrderCallbackData.oppositeAmountXSpotDecimals = quoteTokenAcquired;
            } else {
                quoteTokenAcquired = _formatPerpToSpotQuoteDecimals(amount);
                uint256 oppositeAmountXSpotDecimals = _uniswapV3ExactOutput(
                    UniswapV3ExactOutputParams({
                        tokenIn: address(_getSpotHedgeBaseMakerStorage().baseToken),
                        tokenOut: address(_getSpotHedgeBaseMakerStorage().quoteToken),
                        path: path,
                        recipient: maker,
                        amountOut: quoteTokenAcquired,
                        amountInMaximum: _getSpotHedgeBaseMakerStorage().baseToken.balanceOf(maker)
                    })
                );
                oppositeAmount = _formatSpotToPerpBaseDecimals(oppositeAmountXSpotDecimals);
                // Currently we don't utilize fillOrderCallback for B2Q swaps,
                // but we still populate the arguments anyways.
                fillOrderCallbackData.amountXSpotDecimals = quoteTokenAcquired;
                fillOrderCallbackData.oppositeAmountXSpotDecimals = oppositeAmountXSpotDecimals;
            }

            // Deposit the acquired quote tokens to Vault.
            _deposit(vault, _marketId, quoteTokenAcquired);
        } else {
            // Note we only quote amountIn/Out here and do the swap later in callback.
            // It is because we are not sure how much USDC the maker could withdraw yet,
            // because there are potential PnL to be realized after fillOrder(), after the positions are settled,
            // which may change the maker's free USDC. If we withdraw now, chances are the maker could fall below
            // margin requirement after PnLs are realized, or the maker might not have enough USDC to
            // withdraw yet unless we wait until the PnLs are realized.
            // The best solution is to defer the withdrawal to the callback and withdraw only after
            // the positions are settled and PnLs are realized.
            path = _getPath(
                address(_getSpotHedgeBaseMakerStorage().quoteToken),
                address(_getSpotHedgeBaseMakerStorage().baseToken),
                isExactInput
            );

            if (isExactInput) {
                uint256 quoteTokenRequired = _formatPerpToSpotQuoteDecimals(amount);
                // get quote
                uint256 oppositeAmountXSpotDecimals = _getSpotHedgeBaseMakerStorage().uniswapV3Quoter.quoteExactInput(
                    path,
                    quoteTokenRequired
                );
                oppositeAmount = _formatSpotToPerpBaseDecimals(oppositeAmountXSpotDecimals);

                fillOrderCallbackData.amountXSpotDecimals = quoteTokenRequired;
                fillOrderCallbackData.oppositeAmountXSpotDecimals = oppositeAmountXSpotDecimals;
            } else {
                uint256 baseTokenRequired = _formatPerpToSpotBaseDecimals(amount);
                // get quote
                uint256 oppositeAmountXSpotDecimals = _getSpotHedgeBaseMakerStorage().uniswapV3Quoter.quoteExactOutput(
                    path,
                    baseTokenRequired
                );
                oppositeAmount = _formatSpotToPerpQuoteDecimals(oppositeAmountXSpotDecimals);

                fillOrderCallbackData.amountXSpotDecimals = baseTokenRequired;
                fillOrderCallbackData.oppositeAmountXSpotDecimals = oppositeAmountXSpotDecimals;
            }
        }

        emit SHMOrderFilled(
            _getSpotHedgeBaseMakerStorage().marketId,
            path,
            isBaseToQuote,
            isExactInput,
            amount, // targetAmount
            oppositeAmount,
            0 // spread
        );

        return (oppositeAmount, abi.encode(fillOrderCallbackData));
    }

    //
    // EXTERNAL VIEW
    //

    function getUniswapV3Path(address tokenIn, address tokenOut) external view returns (bytes memory) {
        return _getSpotHedgeBaseMakerStorage().uniswapV3PathMap[_getKey(tokenIn, tokenOut)];
    }

    // Ratio decimals = INTERNAL_DECIMALS
    function getUtilRatio() external view returns (uint256, uint256) {
        if (_getSpotHedgeBaseMakerStorage().baseTokenLiability == 0) {
            return (0, 0);
        }

        // shortCapacityRatio = BaseBalance / BaseLiability
        uint256 shortCapacityRatio = (WAD * _getSpotHedgeBaseMakerStorage().baseToken.balanceOf(address(this))) /
            _getSpotHedgeBaseMakerStorage().baseTokenLiability;

        uint256 shortUtilRatio;
        if ((WAD >= shortCapacityRatio)) {
            shortUtilRatio = WAD - shortCapacityRatio;
        }
        return (0, shortUtilRatio);
    }

    function isValidSender(address) external pure override returns (bool) {
        return true;
    }

    function getAsset() external view returns (address) {
        return address(_getSpotHedgeBaseMakerStorage().baseToken);
    }

    function getTotalAssets(uint256 price) external view returns (int256) {
        return
            _getVaultValueInBase(_getVault(), price).formatDecimals(
                INTERNAL_DECIMALS,
                _getSpotHedgeBaseMakerStorage().baseToken.decimals()
            );
    }

    // For backward-compatibility
    function marketId() external view returns (uint256) {
        return _getSpotHedgeBaseMakerStorage().marketId;
    }

    // For backward-compatibility
    function baseToken() external view returns (IERC20Metadata) {
        return _getSpotHedgeBaseMakerStorage().baseToken;
    }

    // For backward-compatibility
    function quoteToken() external view returns (IERC20Metadata) {
        return _getSpotHedgeBaseMakerStorage().quoteToken;
    }

    // For backward-compatibility
    function baseTokenDecimals() external view returns (uint8) {
        return _getSpotHedgeBaseMakerStorage().baseTokenDecimals;
    }

    // For backward-compatibility
    function quoteTokenDecimals() external view returns (uint8) {
        return _getSpotHedgeBaseMakerStorage().quoteTokenDecimals;
    }

    // For backward-compatibility
    function baseTokenLiability() external view returns (uint256) {
        return _getSpotHedgeBaseMakerStorage().baseTokenLiability;
    }

    // For backward-compatibility
    function minMarginRatio() external view returns (uint256) {
        return _getSpotHedgeBaseMakerStorage().minMarginRatio;
    }

    //
    // INTERNAL NON-VIEW
    //

    function _deposit(IVault vault, uint256 _marketId, uint256 amount) internal {
        _getSpotHedgeBaseMakerStorage().quoteToken.approve(address(vault), amount);
        vault.deposit(address(this), amount);
        vault.transferFundToMargin(_marketId, amount);
    }

    function _withdraw(IVault vault, uint256 _marketId, uint256 amount) internal {
        vault.transferMarginToFund(_marketId, amount);
        vault.withdraw(amount);
    }

    function _uniswapV3ExactInput(UniswapV3ExactInputParams memory params) internal returns (uint256 amountOut) {
        IERC20Metadata(params.tokenIn).approve(
            address(_getSpotHedgeBaseMakerStorage().uniswapV3Router),
            params.amountIn
        );

        return
            _getSpotHedgeBaseMakerStorage().uniswapV3Router.exactInput(
                ISwapRouter.ExactInputParams({
                    path: params.path,
                    recipient: params.recipient, // transfer tokenOut directly to recipient
                    deadline: block.timestamp,
                    amountIn: params.amountIn,
                    amountOutMinimum: params.amountOutMinimum
                })
            );
    }

    function _uniswapV3ExactOutput(UniswapV3ExactOutputParams memory params) internal returns (uint256 amountIn) {
        IERC20Metadata tokenIn = IERC20Metadata(params.tokenIn);
        tokenIn.approve(address(_getSpotHedgeBaseMakerStorage().uniswapV3Router), tokenIn.balanceOf(address(this)));

        // might revert at this step, if amount in > free collateral
        amountIn = _getSpotHedgeBaseMakerStorage().uniswapV3Router.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: params.path,
                recipient: params.recipient, // transfer tokenOut directly to recipient
                deadline: block.timestamp,
                amountOut: params.amountOut,
                amountInMaximum: params.amountInMaximum
            })
        );

        tokenIn.approve(address(_getSpotHedgeBaseMakerStorage().uniswapV3Router), 0);
        return amountIn;
    }

    function _fillOrderCallback(FillOrderCallbackData memory data) internal {
        if (data.isBaseToQuote) {
            // do nothing
            return;
        }

        (address tokenIn, address tokenOut) = (
            address(_getSpotHedgeBaseMakerStorage().quoteToken),
            address(_getSpotHedgeBaseMakerStorage().baseToken)
        );
        address maker = address(this);
        uint256 _marketId = _getSpotHedgeBaseMakerStorage().marketId;
        IVault vault = _getVault();

        bytes memory path;
        // Note we don't explicitly check maker's quote asset balance because
        // if it is insufficient, it would revert in swap anyways.
        if (data.isExactInput) {
            _withdraw(vault, _marketId, data.amountXSpotDecimals);
            path = _getPath(
                tokenIn,
                tokenOut,
                true // isExactInput
            );
            _uniswapV3ExactInput(
                UniswapV3ExactInputParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    path: path,
                    recipient: maker,
                    amountIn: data.amountXSpotDecimals,
                    amountOutMinimum: data.oppositeAmountXSpotDecimals
                })
            );
            return;
        }

        // else = if data.isExactOutput
        _withdraw(vault, _marketId, data.oppositeAmountXSpotDecimals);
        path = _getPath(
            tokenIn,
            tokenOut,
            false // isExactInput
        );
        _uniswapV3ExactOutput(
            UniswapV3ExactOutputParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                path: path,
                recipient: maker,
                amountOut: data.amountXSpotDecimals,
                amountInMaximum: data.oppositeAmountXSpotDecimals
            })
        );

        uint256 remainQuoteTokenAmount = _getSpotHedgeBaseMakerStorage().quoteToken.balanceOf(maker);
        if (remainQuoteTokenAmount > 0) {
            _deposit(vault, _marketId, remainQuoteTokenAmount);
        }
    }

    //
    // INTERNAL VIEW
    //
    function _getVault() internal view returns (IVault) {
        return getAddressManager().getVault();
    }

    function _checkMinMarginRatio(uint256 price) internal view {
        int256 marginRatio = _getVault().getMarginRatio(_getSpotHedgeBaseMakerStorage().marketId, address(this), price);
        int256 minMarginRatio_ = _getSpotHedgeBaseMakerStorage().minMarginRatio.toInt256();
        if (marginRatio < minMarginRatio_) revert LibError.MinMarginRatioExceeded(marginRatio, minMarginRatio_);
    }

    function _getPath(address tokenIn, address tokenOut, bool isExactInput) internal view returns (bytes memory path) {
        (address tokenA, address tokenB) = (isExactInput)
            ? (tokenIn, tokenOut) // Note the ordering of tokenIn/tokenOut is switched because // Uniswap SwapRouter.exactOutput() takes path in reversed order.
            : (tokenOut, tokenIn);

        path = _getSpotHedgeBaseMakerStorage().uniswapV3PathMap[_getKey(tokenA, tokenB)];
        if (keccak256(path) == keccak256(bytes(""))) revert LibError.PathNotSet(tokenA, tokenB);

        return path;
    }

    // solhint-disable-next-line max-line-length
    // Forked from https://github.com/perpetual-protocol/kantaban-contract/blob/18e0c1fe16490ccc9cbf0d9514e2204964f31624/contracts/Router.sol#L86-L118
    function _verifyPath(address expectedTokenIn, address expectedTokenOut, bytes memory path) internal view {
        address firstTokenIn = path.toAddress(0);

        if (firstTokenIn != expectedTokenIn) revert LibError.UnexpectedPathTokenIn(firstTokenIn, expectedTokenIn);

        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();
            bytes memory pool = path.getFirstPool();

            (address tokenIn, address tokenOut, uint24 fee) = pool.decodeFirstPool();

            address poolAddress = IUniswapV3Factory(_getSpotHedgeBaseMakerStorage().uniswapV3Factory).getPool(
                tokenIn,
                tokenOut,
                fee
            );

            if (poolAddress == address(0)) revert LibError.ZeroPoolAddress(tokenIn, tokenOut, fee);

            if (hasMultiplePools) {
                path = path.skipToken();
                continue;
            }

            // else = hasSinglePool
            if (tokenOut != expectedTokenOut) revert LibError.UnexpectedPathTokenOut(tokenOut, expectedTokenOut);
            break;
        }
    }

    function _getVaultValueInBase(IVault vault, uint256 price) internal view returns (int256) {
        int256 accountValue = vault.getAccountValue(_getSpotHedgeBaseMakerStorage().marketId, address(this), price);
        int256 accountValueInBase = (accountValue * WAD.toInt256()) / price.toInt256();
        int256 spotValueInBase = _getSpotHedgeBaseMakerStorage()
            .baseToken
            .balanceOf(address(this))
            .formatDecimals(_getSpotHedgeBaseMakerStorage().baseTokenDecimals, INTERNAL_DECIMALS)
            .toInt256();
        return accountValueInBase + spotValueInBase;
    }

    function _getVaultValueInBaseSafe(IVault vault, uint256 price) internal view returns (uint256) {
        // Revert early since we don't allow deposit/withdraw when the vault's value is negative or zero.
        int256 vaultValueInBase = _getVaultValueInBase(vault, price);
        if (vaultValueInBase <= 0) revert LibError.NegativeOrZeroVaultValueInBase(vaultValueInBase);

        return vaultValueInBase.toUint256();
    }

    function _formatPerpToSpotBaseDecimals(uint256 perpBaseAmount) internal view returns (uint256) {
        return perpBaseAmount.formatDecimals(INTERNAL_DECIMALS, _getSpotHedgeBaseMakerStorage().baseTokenDecimals);
    }

    function _formatPerpToSpotQuoteDecimals(uint256 perpQuoteAmount) internal view returns (uint256) {
        return perpQuoteAmount.formatDecimals(INTERNAL_DECIMALS, _getSpotHedgeBaseMakerStorage().quoteTokenDecimals);
    }

    function _formatSpotToPerpBaseDecimals(uint256 spotBaseAmount) internal view returns (uint256) {
        return spotBaseAmount.formatDecimals(_getSpotHedgeBaseMakerStorage().baseTokenDecimals, INTERNAL_DECIMALS);
    }

    function _formatSpotToPerpQuoteDecimals(uint256 spotQuoteAmount) internal view returns (uint256) {
        return spotQuoteAmount.formatDecimals(_getSpotHedgeBaseMakerStorage().quoteTokenDecimals, INTERNAL_DECIMALS);
    }

    function _getPrice() internal view returns (uint256) {
        IAddressManager addressManager = getAddressManager();
        (uint256 price, ) = addressManager.getPythOracleAdapter().getPrice(
            addressManager.getConfig().getPriceFeedId(_getSpotHedgeBaseMakerStorage().marketId)
        );
        return price;
    }

    //
    // INTERNAL PURE
    //

    // solhint-disable-next-line max-line-length
    // Forked from https://github.com/perpetual-protocol/kantaban-contract/blob/18e0c1fe16490ccc9cbf0d9514e2204964f31624/contracts/Router.sol#L124C4-L126
    function _getKey(address tokenIn, address tokenOut) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    //
    // PRIVATE
    //

    function _getSpotHedgeBaseMakerStorage() private pure returns (SpotHedgeBaseMakerStorage storage $) {
        assembly {
            $.slot := _SPOT_HEDGE_BASE_MAKER_STORAGE_LOCATION
        }
    }
}
