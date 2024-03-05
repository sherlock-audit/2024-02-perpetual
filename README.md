
# Perpetual contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Optimism/Blast
___

### Q: Which ERC20 tokens do you expect will interact with the smart contracts? 
- USDT or USDC
- Except `SpotHedgeBaseMaker`: it may also interact with other non-collateral tokens as part of its hedging strategy, these tokens are assumed not to possess any "weird" traits.
___

### Q: Which ERC721 tokens do you expect will interact with the smart contracts? 
None
___

### Q: Do you plan to support ERC1155?
No
___

### Q: Which ERC777 tokens do you expect will interact with the smart contracts? 
None
___

### Q: Are there any FEE-ON-TRANSFER tokens interacting with the smart contracts?

No
___

### Q: Are there any REBASING tokens interacting with the smart contracts?

No
___

### Q: Are the admins of the protocols your contracts integrate with (if any) TRUSTED or RESTRICTED?
TRUSTED
___

### Q: Is the admin/owner of the protocol/contracts TRUSTED or RESTRICTED?
TRUSTED
___

### Q: Are there any additional protocol roles? If yes, please explain in detail:
1. Relayer
2. Relayer is a permissioned address controlled by us, it'll be used to help users settle their off-chain orders(limit order, market order) on chain.
3. Match users orders and charge the relayer fee
4. Apart from matching the user's order, no additional losses should be incurred by the relayer. The relayer may have some value extraction strategies available (for example by delaying the execution of the orders), and is trusted not to use them.
___

### Q: Is the code/contract expected to comply with any EIPs? Are there specific assumptions around adhering to those EIPs that Watsons should be aware of?
The core protocol does not comply with any EIPs. Some components may comply with EIPs like EIP-7265 (Circuit Breaker), ERC-7412, but we may customize the code according to our needs and we do not expect composability in these parts.
___

### Q: Please list any known issues/acceptable risks that should not result in a valid finding.
1. Ownable’s owner could potentially disrupt regular operation through the disabling of features, incorrect setting of values, whitelisting malicious tokens, etc
2. Oracle (Pyth) is expected to accurately report the price of market
3. OrderGatewayV2’s relayer may not postpone order enough for mitigating others front-run oracle if the maker is OracleMaker
4. LP deposit and withdrawal of OracleMaker and SpotHedgeBaseMaker is designed to simplify asset transfer in the majority of the cases; however, it is not guaranteed in edge cases when the collateral is low (or when the utilization is high)
5. LP of SpotHedgedBaseMaker withdraw may change `maker.getUtilRatio`, but didn't trigger `_updateUtilRatio`
6. OracleMaker/SpotHedgedBaseMaker doesn’t handle inflation attacks when minting/burning shares
7. SpotHedgedBaseMaker could trigger CircuitBreaker rate limit when swap/withdraw
8. `OracleMaker.fillOrder()` has hardcoded decimals instead of using `INTERNAL_DECIMALS`
9. FundingFee will be incorrect if Config’s owner did not trigger FundingFee’s `_updateFundingGrowthIndex` when changing FundingConfig or imRatio
10. In CircuitBreaker LibLimiter, `limiter.listNodes[currentHead]` not actually deleted
11. In CircuitBreaker LibLimiter, `limiter.listHead/listTail` no initially set to `currentTickTimestamp`
12. When the maker's margin ratio is below the minimum margin ratio, only trading that raises it above the minimum margin ratio is accepted, even if it involves reducing the maker’s position (which might increase the ratio)
13. PnL Pool currently starts empty, so a trader with realized gains may experience temporary illiquidity when he tries to withdraw those gains. This inconvenience will be mitigated in the future with a buffer balance
14. ClearingHouse may has some surplus margin (from liquidation fee) that can not be withdrawn by anyone yet
___

### Q: Please provide links to previous audits (if any).
N/A
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, input validation expectations, etc)?
1. we're using off-chain oracle (Pyth) to fetch the price of assets, when interacting with the protocol, user first obtains a signed price through API, then updates this price to the protocol and interacts.
2. users can submit off-chain orders(limit order, market order) to our backend system through API, and our relayers will settle those orders on-chain through OrderGatewayV2
___

### Q: In case of external protocol integrations, are the risks of external contracts pausing or executing an emergency withdrawal acceptable? If not, Watsons will submit issues related to these situations that can harm your protocol's functionality.
Yes it should be acceptable.
___

### Q: Do you expect to use any of the following tokens with non-standard behaviour with the smart contracts?
We will use USDT on OP, not on this list since it’s a bridged token.
___

### Q: Add links to relevant protocol resources
https://perp.notion.site/Perp-v3-11275f0dcb914b3a992d9c7f915f2c0c?pvs=4
___



# Audit scope


[perp-contract-v3 @ 8b850742b29ef6cc93d0988dc6eff91506972111](https://github.com/perpetual-protocol/perp-contract-v3/tree/8b850742b29ef6cc93d0988dc6eff91506972111)
- [perp-contract-v3/src/addressManager/AddressManager.sol](perp-contract-v3/src/addressManager/AddressManager.sol)
- [perp-contract-v3/src/addressManager/IAddressManager.sol](perp-contract-v3/src/addressManager/IAddressManager.sol)
- [perp-contract-v3/src/addressResolver/AddressResolverUpgradeable.sol](perp-contract-v3/src/addressResolver/AddressResolverUpgradeable.sol)
- [perp-contract-v3/src/addressResolver/LibAddressResolver.sol](perp-contract-v3/src/addressResolver/LibAddressResolver.sol)
- [perp-contract-v3/src/authorization/AuthorizationUpgradeable.sol](perp-contract-v3/src/authorization/AuthorizationUpgradeable.sol)
- [perp-contract-v3/src/authorization/IAuthorization.sol](perp-contract-v3/src/authorization/IAuthorization.sol)
- [perp-contract-v3/src/borrowingFee/BorrowingFee.sol](perp-contract-v3/src/borrowingFee/BorrowingFee.sol)
- [perp-contract-v3/src/borrowingFee/BorrowingFeeModel.sol](perp-contract-v3/src/borrowingFee/BorrowingFeeModel.sol)
- [perp-contract-v3/src/borrowingFee/BorrowingFeeStruct.sol](perp-contract-v3/src/borrowingFee/BorrowingFeeStruct.sol)
- [perp-contract-v3/src/borrowingFee/IBorrowingFee.sol](perp-contract-v3/src/borrowingFee/IBorrowingFee.sol)
- [perp-contract-v3/src/borrowingFee/IBorrowingFeeEvent.sol](perp-contract-v3/src/borrowingFee/IBorrowingFeeEvent.sol)
- [perp-contract-v3/src/borrowingFee/LibBorrowingFee.sol](perp-contract-v3/src/borrowingFee/LibBorrowingFee.sol)
- [perp-contract-v3/src/borrowingFee/LibFeeGrowthGlobal.sol](perp-contract-v3/src/borrowingFee/LibFeeGrowthGlobal.sol)
- [perp-contract-v3/src/circuitBreaker/CircuitBreaker.sol](perp-contract-v3/src/circuitBreaker/CircuitBreaker.sol)
- [perp-contract-v3/src/circuitBreaker/ICircuitBreaker.sol](perp-contract-v3/src/circuitBreaker/ICircuitBreaker.sol)
- [perp-contract-v3/src/circuitBreaker/LibLimiter.sol](perp-contract-v3/src/circuitBreaker/LibLimiter.sol)
- [perp-contract-v3/src/circuitBreaker/LimiterStructs.sol](perp-contract-v3/src/circuitBreaker/LimiterStructs.sol)
- [perp-contract-v3/src/clearingHouse/ClearingHouse.sol](perp-contract-v3/src/clearingHouse/ClearingHouse.sol)
- [perp-contract-v3/src/clearingHouse/IClearingHouse.sol](perp-contract-v3/src/clearingHouse/IClearingHouse.sol)
- [perp-contract-v3/src/clearingHouse/LibLiquidation.sol](perp-contract-v3/src/clearingHouse/LibLiquidation.sol)
- [perp-contract-v3/src/common/ContextBase.sol](perp-contract-v3/src/common/ContextBase.sol)
- [perp-contract-v3/src/common/LibConstant.sol](perp-contract-v3/src/common/LibConstant.sol)
- [perp-contract-v3/src/common/LibError.sol](perp-contract-v3/src/common/LibError.sol)
- [perp-contract-v3/src/common/LibFormatter.sol](perp-contract-v3/src/common/LibFormatter.sol)
- [perp-contract-v3/src/common/LugiaMath.sol](perp-contract-v3/src/common/LugiaMath.sol)
- [perp-contract-v3/src/config/Config.sol](perp-contract-v3/src/config/Config.sol)
- [perp-contract-v3/src/config/FundingConfig.sol](perp-contract-v3/src/config/FundingConfig.sol)
- [perp-contract-v3/src/external/universalSigValidator/IUniversalSigValidator.sol](perp-contract-v3/src/external/universalSigValidator/IUniversalSigValidator.sol)
- [perp-contract-v3/src/external/universalSigValidator/UniversalSigValidator.sol](perp-contract-v3/src/external/universalSigValidator/UniversalSigValidator.sol)
- [perp-contract-v3/src/fundingFee/FundingFee.sol](perp-contract-v3/src/fundingFee/FundingFee.sol)
- [perp-contract-v3/src/fundingFee/IFundingFee.sol](perp-contract-v3/src/fundingFee/IFundingFee.sol)
- [perp-contract-v3/src/maker/IMaker.sol](perp-contract-v3/src/maker/IMaker.sol)
- [perp-contract-v3/src/maker/IWhitelistLpManager.sol](perp-contract-v3/src/maker/IWhitelistLpManager.sol)
- [perp-contract-v3/src/maker/OracleMaker.sol](perp-contract-v3/src/maker/OracleMaker.sol)
- [perp-contract-v3/src/maker/SpotHedgeBaseMaker.sol](perp-contract-v3/src/maker/SpotHedgeBaseMaker.sol)
- [perp-contract-v3/src/maker/WhitelistLpManager.sol](perp-contract-v3/src/maker/WhitelistLpManager.sol)
- [perp-contract-v3/src/makerReporter/IMakerReporter.sol](perp-contract-v3/src/makerReporter/IMakerReporter.sol)
- [perp-contract-v3/src/makerReporter/MakerReporter.sol](perp-contract-v3/src/makerReporter/MakerReporter.sol)
- [perp-contract-v3/src/oracle/pythOracleAdapter/IPythOracleAdapter.sol](perp-contract-v3/src/oracle/pythOracleAdapter/IPythOracleAdapter.sol)
- [perp-contract-v3/src/oracle/pythOracleAdapter/PythOracleAdapter.sol](perp-contract-v3/src/oracle/pythOracleAdapter/PythOracleAdapter.sol)
- [perp-contract-v3/src/orderGatewayV2/LibOrder.sol](perp-contract-v3/src/orderGatewayV2/LibOrder.sol)
- [perp-contract-v3/src/orderGatewayV2/OrderGatewayV2.sol](perp-contract-v3/src/orderGatewayV2/OrderGatewayV2.sol)
- [perp-contract-v3/src/quoter/Quoter.sol](perp-contract-v3/src/quoter/Quoter.sol)
- [perp-contract-v3/src/systemStatus/ISystemStatus.sol](perp-contract-v3/src/systemStatus/ISystemStatus.sol)
- [perp-contract-v3/src/systemStatus/SystemStatus.sol](perp-contract-v3/src/systemStatus/SystemStatus.sol)
- [perp-contract-v3/src/vault/FundModelUpgradeable.sol](perp-contract-v3/src/vault/FundModelUpgradeable.sol)
- [perp-contract-v3/src/vault/IMarginProfile.sol](perp-contract-v3/src/vault/IMarginProfile.sol)
- [perp-contract-v3/src/vault/IPositionModelEvent.sol](perp-contract-v3/src/vault/IPositionModelEvent.sol)
- [perp-contract-v3/src/vault/IVault.sol](perp-contract-v3/src/vault/IVault.sol)
- [perp-contract-v3/src/vault/LibMargin.sol](perp-contract-v3/src/vault/LibMargin.sol)
- [perp-contract-v3/src/vault/LibPosition.sol](perp-contract-v3/src/vault/LibPosition.sol)
- [perp-contract-v3/src/vault/LibPositionModel.sol](perp-contract-v3/src/vault/LibPositionModel.sol)
- [perp-contract-v3/src/vault/MarginProfile.sol](perp-contract-v3/src/vault/MarginProfile.sol)
- [perp-contract-v3/src/vault/PositionChangedReason.sol](perp-contract-v3/src/vault/PositionChangedReason.sol)
- [perp-contract-v3/src/vault/PositionModelStruct.sol](perp-contract-v3/src/vault/PositionModelStruct.sol)
- [perp-contract-v3/src/vault/PositionModelUpgradeable.sol](perp-contract-v3/src/vault/PositionModelUpgradeable.sol)
- [perp-contract-v3/src/vault/Vault.sol](perp-contract-v3/src/vault/Vault.sol)

