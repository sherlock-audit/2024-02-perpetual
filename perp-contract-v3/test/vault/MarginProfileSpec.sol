// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "../BaseTest.sol";
import "./VaultSpecSetup.sol";
import "../../src/vault/MarginProfile.sol";
import "../../src/vault/LibMargin.sol";

// assume 0 pending margin, 0 pnl pool balance
contract TestMarginProfile is MarginProfile {
    int256 public _margin;
    uint256 public _freeMargin;
    int256 public _openNotional;
    int256 public _posSize;

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function getMargin(uint256, address) public view override returns (int256) {
        return _margin;
    }

    function getFreeMargin(uint256, address) public view override returns (uint256) {
        return _freeMargin;
    }

    function getOpenNotional(uint256, address) public view override returns (int256) {
        return _openNotional;
    }

    function getPositionSize(uint256, address) public view override returns (int256) {
        return _posSize;
    }

    function _getInitialMarginRatio(uint256) internal pure override returns (uint256) {
        return 0.1 ether; //10%
    }

    function _getMaintenanceMarginRatio(uint256) internal pure override returns (uint256) {
        return 0.05 ether; // 5%
    }

    function exposed_setMargin(int256 margin) public {
        _margin = margin;
    }

    function exposed_setFreeMargin(uint256 freeMargin) public {
        _freeMargin = freeMargin;
    }

    function exposed_setMarginAndFreeMargin(int256 margin, uint256 freeMargin) public {
        exposed_setMargin(margin);
        exposed_setFreeMargin(freeMargin);
    }

    function exposed_setPosition(int256 size, int256 openNotional) public {
        _posSize = size;
        _openNotional = openNotional;
    }
}

contract MarginProfileSpec is BaseTest {
    TestMarginProfile profile;
    uint256 public marketId = 0;
    address public any = makeAddr("any");

    // ALL TEST CASES START WITH LONG OR SHORT 1 ETH at $100
    function setUp() public {
        profile = new TestMarginProfile();
    }

    function test_InitialMarginRequirement() public {
        // long 1 eth@$100, imRatio=10%, imRequirement=10
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getMarginRequirement(marketId, any, MarginRequirementType.INITIAL), 10);

        // short 1 eth@$100, imRatio=10%, imRequirement=10
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getMarginRequirement(marketId, any, MarginRequirementType.INITIAL), 10);
    }

    function test_MaintenanceMarginRequirement() public {
        // long 1 eth@$100, mmRatio=5%%, imRequirement=5
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getMarginRequirement(marketId, any, MarginRequirementType.MAINTENANCE), 5);

        // short 1 eth@$100, imRatio=5%, imRequirement=15
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getMarginRequirement(marketId, any, MarginRequirementType.MAINTENANCE), 5);
    }

    function test_UnrealizedPnl() public {
        // long@100, now 50, uPnl=-50
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getUnrealizedPnl(marketId, any, 50 ether), -50);

        // short@100, now 50, uPnl=+50
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getUnrealizedPnl(marketId, any, 50 ether), 50);
    }

    function test_AccountValue() public {
        // margin=10, long@100, now 50, uPnl=-50, accVal = -40
        profile.exposed_setMargin(10);
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getAccountValue(marketId, any, 50 ether), -40);

        // margin=10, short@100, now 50, uPnl=+50, accVal = 60
        profile.exposed_setMargin(10);
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getAccountValue(marketId, any, 50 ether), 60);
    }

    function test_MarginRatio() public {
        // when 0 position, mRatio = max
        assertEq(profile.getMarginRatio(marketId, any, 50 ether), type(int256).max);

        // margin=10, long@100, now 50. acc value=10-50=-40, mRatio=-40/100
        profile.exposed_setMargin(10);
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getMarginRatio(marketId, any, 50 ether), -0.4 ether);

        // margin=10, short@100, now 50, acc value=10+50=60, mRatio=60%
        profile.exposed_setMargin(10);
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getMarginRatio(marketId, any, 50 ether), 0.6 ether);
    }

    function test_FreeCollateral_FreeMarginEqualsMargin() public {
        // margin=10, long@100, now 50, freeCollateral=0
        profile.exposed_setMarginAndFreeMargin(10, 10);
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 0);

        // margin=200, freeCollateral=min(200, 150)-100*10%=140
        profile.exposed_setMarginAndFreeMargin(200, 200);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 140);

        // margin=10, short@100, now 50, freeCollateral=0
        profile.exposed_setMarginAndFreeMargin(10, 10);
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 0);

        // margin=200, freeCollateral=min(200, 250)-100*10%=190
        profile.exposed_setMarginAndFreeMargin(200, 200);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 190);
    }

    function test_FreeCollateral_FreeMarginLessThanMargin() public {
        // margin=10, long@100, now 50, freeCollateral=0
        profile.exposed_setMarginAndFreeMargin(10, 5);
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 0);

        // margin=200, freeCollateral=min(100, 150)-100*10%=90
        profile.exposed_setMarginAndFreeMargin(200, 100);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 90);

        // margin=10, short@100, now 50, freeCollateral=0
        profile.exposed_setMarginAndFreeMargin(10, 5);
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 0);

        // margin=200, freeCollateral=min(100, 250)-100*10%=90
        profile.exposed_setMarginAndFreeMargin(200, 100);
        assertEq(profile.getFreeCollateral(marketId, any, 50 ether), 90);
    }

    function test_FreeCollateralForTrade_FreeMarginEqualsMargin() public {
        // margin=10, long@100, now 50, freeCollateralForTrade(imRatio)=-50, mmRatio=-50
        profile.exposed_setMarginAndFreeMargin(10, 10);
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), -50);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), -45);

        // margin=200, freeCollateralForTrade=min(200, 150)-100*10%=140
        profile.exposed_setMarginAndFreeMargin(200, 200);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), 140);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), 145);

        // margin=10, short@100, now 50, freeCollateral=0
        profile.exposed_setMarginAndFreeMargin(10, 10);
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), 0);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), 5);

        // margin=200, freeCollateral=min(200, 250)-100*10%=190
        profile.exposed_setMarginAndFreeMargin(200, 200);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), 190);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), 195);
    }

    // same result as test_FreeCollateralForTrade_FreeMarginEqualsMargin
    function test_FreeCollateralForTrade_FreeMarginLessThanMargin() public {
        // margin=10, long@100, now 50, freeCollateralForTrade(imRatio)=-50, mmRatio=-50
        profile.exposed_setMarginAndFreeMargin(10, 5);
        profile.exposed_setPosition(1, -100);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), -50);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), -45);

        // margin=200, freeCollateralForTrade=min(200, 150)-100*10%=140
        profile.exposed_setMarginAndFreeMargin(200, 100);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), 140);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), 145);

        // margin=10, short@100, now 50, freeCollateral=0
        profile.exposed_setMarginAndFreeMargin(10, 5);
        profile.exposed_setPosition(-1, 100);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), 0);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), 5);

        // margin=200, freeCollateral=min(200, 250)-100*10%=190
        profile.exposed_setMarginAndFreeMargin(200, 100);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.INITIAL), 190);
        assertEq(profile.getFreeCollateralForTrade(marketId, any, 50 ether, MarginRequirementType.MAINTENANCE), 195);
    }
}
