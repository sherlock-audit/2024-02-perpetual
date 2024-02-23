// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { IClearingHouse } from "../clearingHouse/IClearingHouse.sol";
import { IVault } from "../vault/IVault.sol";
import { Config } from "../config/Config.sol";
import { OrderGateway } from "../orderGateway/OrderGateway.sol";
import { OrderGatewayV2 } from "../orderGatewayV2/OrderGatewayV2.sol";
import { IAddressManager } from "../addressManager/IAddressManager.sol";
import { IPythOracleAdapter } from "../oracle/pythOracleAdapter/IPythOracleAdapter.sol";
import { IBorrowingFee } from "../borrowingFee/IBorrowingFee.sol";
import { IFundingFee } from "../fundingFee/IFundingFee.sol";
import { IMakerReporter } from "../makerReporter/IMakerReporter.sol";
import { IUniversalSigValidator } from "../external/universalSigValidator/IUniversalSigValidator.sol";
import { ISystemStatus } from "../systemStatus/ISystemStatus.sol";
import { ICircuitBreaker } from "../circuitBreaker/ICircuitBreaker.sol";
import { IWhitelistLpManager } from "../maker/IWhitelistLpManager.sol";

string constant CONFIG = "Config";
string constant VAULT = "Vault";
string constant SYSTEM_STATUS = "SystemStatus";
string constant CIRCUIT_BREAKER = "CircuitBreaker";
string constant CLEARING_HOUSE = "ClearingHouse";
string constant LAZY_MARGIN = "LazyMargin";
string constant BORROWING_FEE = "BorrowingFee";
string constant FUNDING_FEE = "FundingFee";
string constant ORDER_GATEWAY = "OrderGateway";
string constant ORDER_GATEWAY_V2 = "OrderGatewayV2";
string constant PYTH_ORACLE_ADAPTER = "PythOracleAdapter";
string constant MAKER_REPORTER = "MakerReporter";
string constant UNIVERSAL_SIG_VALIDATOR = "UniversalSigValidator";
string constant WHITELIST_LP_MANAGER = "WhitelistLpManager";

library LibAddressResolver {
    function getVault(IAddressManager self) internal view returns (IVault) {
        return IVault(self.getAddress(VAULT));
    }

    function getClearingHouse(IAddressManager self) internal view returns (IClearingHouse) {
        return IClearingHouse(self.getAddress(CLEARING_HOUSE));
    }

    function getBorrowingFee(IAddressManager self) internal view returns (IBorrowingFee) {
        return IBorrowingFee(self.getAddress(BORROWING_FEE));
    }

    function getOrderGateway(IAddressManager self) internal view returns (OrderGateway) {
        return OrderGateway(self.getAddress(ORDER_GATEWAY));
    }

    function getOrderGatewayV2(IAddressManager self) internal view returns (OrderGatewayV2) {
        return OrderGatewayV2(self.getAddress(ORDER_GATEWAY_V2));
    }

    // Used by core contracts: ClearingHouse, Vault, etc.
    function getPythOracleAdapter(IAddressManager self) internal view returns (IPythOracleAdapter) {
        return IPythOracleAdapter(self.getAddress(PYTH_ORACLE_ADAPTER));
    }

    function getConfig(IAddressManager self) internal view returns (Config) {
        return Config(self.getAddress(CONFIG));
    }

    function getFundingFee(IAddressManager self) internal view returns (IFundingFee) {
        return IFundingFee(self.getAddress(FUNDING_FEE));
    }

    function getMakerReporter(IAddressManager self) internal view returns (IMakerReporter) {
        return IMakerReporter(self.getAddress(MAKER_REPORTER));
    }

    function getUniversalSigValidator(IAddressManager self) internal view returns (IUniversalSigValidator) {
        return IUniversalSigValidator(self.getAddress(UNIVERSAL_SIG_VALIDATOR));
    }

    function getSystemStatus(IAddressManager self) internal view returns (ISystemStatus) {
        return ISystemStatus(self.getAddress(SYSTEM_STATUS));
    }

    function getCircuitBreaker(IAddressManager self) internal view returns (ICircuitBreaker) {
        return ICircuitBreaker(self.getAddress(CIRCUIT_BREAKER));
    }

    function getWhitelistLpManager(IAddressManager self) internal view returns (IWhitelistLpManager) {
        return IWhitelistLpManager(self.getAddress(WHITELIST_LP_MANAGER));
    }
}
