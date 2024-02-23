# lugia-contract

## Dependencies

We use Foundry to manage contract dependencies (actually, Foundry is using `.gitmodules`). However, we still add contract dependencies to `package.json` to get vulnerability alerts using [Dependabot](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-supply-chain-security).

Therefore, please make sure you update both `.gitmodules` and `package.json` when changing contract dependencies.

## Environment Variables

Make sure you have `.env` file at project root with the following variables:

```shell
OPTIMISM_WEB3_ENDPOINT_ARCHIVE // Optimism archive endpoint
```

## Unit Tests

For unit tests, basically we follow the best practices of [Foundry](https://book.getfoundry.sh/tutorials/best-practices#tests).

If you want to test a case that expecting a revert, add `_reverts` suffix to the function name, example:

```solidity
function test_deposit_reverts() public {
    // ...
}
```

## Git branch convention
If you are not sure when to merge into `main`, please reference the [doc](https://www.notion.so/perp/Git-flow-for-lugia-contract-a051217562c14a75ac59adcfc304f7fd?pvs=4).

## Commands
To install all dependencies:
```shell
 npm ci
 forge install
```
To compile contracts:
```shell
npm run build
# or
forge build
```
To run all tests:
```shell
npm run test
# or
forge test
```
