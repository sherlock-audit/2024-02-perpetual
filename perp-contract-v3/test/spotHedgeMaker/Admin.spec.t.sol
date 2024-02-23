// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Factory } from "../../src/external/uniswap-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { LibError } from "../../src/common/LibError.sol";
import { SpotHedgeBaseMaker } from "../../src/maker/SpotHedgeBaseMaker.sol";
import { TestDeflationaryToken } from "../helper/TestDeflationaryToken.sol";
import { SpotHedgeBaseMakerSpecSetup } from "./SpotHedgeBaseMakerSpecSetup.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SpotHedgeBaseMakerAdminSpec is SpotHedgeBaseMakerSpecSetup {
    SpotHedgeBaseMaker public maker;
    address public someone = makeAddr("SOME-ONE");
    address newUniswapV3Router = makeAddr("New-UniswapV3Router");
    address newUniswapV3Factory = makeAddr("New-UniswapV3Factory");

    function setUp() public virtual override {
        SpotHedgeBaseMakerSpecSetup.setUp();

        maker = _create_Maker();
    }

    function test_setUniswapV3Router_Normal() public {
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.UniswapV3RouterSet(newUniswapV3Router, uniswapV3Router);
        maker.setUniswapV3Router(newUniswapV3Router);
    }

    function test_setUniswapV3Router_RevertIf_non_admin() public {
        vm.startPrank(someone);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, someone));
        maker.setUniswapV3Router(newUniswapV3Router);
        vm.stopPrank();
    }

    function test_setUniswapV3Router_RevertIf_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAddress.selector));
        maker.setUniswapV3Router(address(0));
    }

    function test_setUniswapV3Factory_Normal() public {
        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.UniswapV3FactorySet(newUniswapV3Factory, uniswapV3Factory);
        maker.setUniswapV3Factory(newUniswapV3Factory);
    }

    function test_setUniswapV3Factory_RevertIf_non_admin() public {
        vm.startPrank(someone);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, someone));
        maker.setUniswapV3Factory(newUniswapV3Factory);
        vm.stopPrank();
    }

    function test_setUniswapV3Factory_RevertIf_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(LibError.ZeroAddress.selector));
        maker.setUniswapV3Factory(address(0));
    }

    function test_setUniswapV3Path_Normal() public {
        address newPool = makeAddr("NEW-POOL");
        bytes memory newUniswapV3B2QPath = abi.encodePacked(address(baseToken), uint24(500), address(quoteToken));

        vm.mockCall(
            address(uniswapV3Factory),
            abi.encodeWithSelector(
                IUniswapV3Factory.getPool.selector,
                address(baseToken),
                address(quoteToken),
                uint24(500)
            ),
            abi.encode(newPool)
        );

        vm.expectEmit(true, true, true, true, address(maker));
        emit SpotHedgeBaseMaker.UniswapV3PathSet(
            address(baseToken),
            address(quoteToken),
            newUniswapV3B2QPath,
            uniswapV3B2QPath
        );
        maker.setUniswapV3Path(address(baseToken), address(quoteToken), newUniswapV3B2QPath);
    }

    function test_setUniswapV3Path_RevertIf_non_admin() public {
        bytes memory newUniswapV3B2QPath = abi.encodePacked(address(baseToken), uint24(500), address(quoteToken));

        vm.startPrank(someone);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, someone));
        maker.setUniswapV3Path(address(baseToken), address(quoteToken), newUniswapV3B2QPath);
        vm.stopPrank();
    }

    function test_setUniswapV3Path_RevertIf_invalid_path() public {
        bytes memory newUniswapV3B2QPath = abi.encodePacked(address(baseToken), uint24(500), address(quoteToken));

        vm.mockCall(
            address(uniswapV3Factory),
            abi.encodeWithSelector(
                IUniswapV3Factory.getPool.selector,
                address(baseToken),
                address(quoteToken),
                uint24(500)
            ),
            abi.encode(address(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LibError.ZeroPoolAddress.selector,
                address(baseToken),
                address(quoteToken),
                uint24(500)
            )
        );
        maker.setUniswapV3Path(address(baseToken), address(quoteToken), newUniswapV3B2QPath);
    }
}
