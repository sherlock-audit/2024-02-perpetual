// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

contract TestERC1271Wallet {
    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    address public owner;

    constructor(address ownerArg) {
        owner = ownerArg;
    }

    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4) {
        // Validate signatures
        if (ECDSA.recover(_hash, _signature) == owner) {
            return MAGICVALUE;
        } else {
            return 0xffffffff;
        }
    }
}

contract Create2Factory {
    function test_excludeFromCoverageReport() public virtual {
        // workaround: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    }

    function deploy(address owner, bytes32 salt) external {
        new TestERC1271Wallet{ salt: salt }(owner);
    }

    function getAddress(bytes32 salt, address walletOwner) external view returns (address) {
        // must call Create2.computeAddress() with the factory itself
        address erc1271Wallet = Create2.computeAddress(
            salt,
            keccak256(abi.encodePacked(type(TestERC1271Wallet).creationCode, abi.encode(walletOwner)))
        );

        return erc1271Wallet;
    }
}
