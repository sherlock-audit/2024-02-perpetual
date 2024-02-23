// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../MockSetup.sol";
import { IPyth } from "pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/PythStructs.sol";
import { OracleMaker } from "../../src/maker/OracleMaker.sol";
import { IPythOracleAdapter } from "../../src/oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { TestDeflationaryToken } from "../helper/TestDeflationaryToken.sol";
import { TestCustomDecimalsToken } from "../helper/TestCustomDecimalsToken.sol";

contract OracleMakerSpecSetup is MockSetup {
    IPyth public pyth = IPyth(makeAddr("PYTH"));
    uint256 public oracleFee = 1; // 1 wei
    TestDeflationaryToken public deflationaryCollateralToken;

    function setUp() public virtual override {
        super.setUp();

        collateralToken = address(new TestCustomDecimalsToken("USDC", "USDC", 6));
        vm.label(collateralToken, ERC20(collateralToken).symbol());
        deflationaryCollateralToken = new TestDeflationaryToken("DF-USDC", "DF-USDC");
        vm.label(address(deflationaryCollateralToken), deflationaryCollateralToken.symbol());

        // override mockVault.getCollateralToken to new custom decimals oken
        vm.mockCall(mockVault, abi.encodeWithSelector(Vault.getCollateralToken.selector), abi.encode(collateralToken));

        vm.mockCall(mockConfig, abi.encodeWithSelector(Config.getPriceFeedId.selector), abi.encode(priceFeedId));
    }

    function test_excludeFromCoverageReport() public override {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    // ex: 1234.56 => price: 123456, expo = -2
    function _mockPythPrice(int64 price, int32 expo) internal {
        PythStructs.Price memory basePythPrice = PythStructs.Price(price, 0, expo, block.timestamp);

        vm.mockCall(
            address(pyth),
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, priceFeedId),
            abi.encode(basePythPrice)
        );
    }

    function _create_OracleMaker() internal returns (OracleMaker) {
        OracleMaker maker = new OracleMaker();
        _enableInitialize(address(maker));
        maker.initialize(marketId, "OM", "OM", mockAddressManager, priceFeedId, 1e18);
        return maker;
    }
}
