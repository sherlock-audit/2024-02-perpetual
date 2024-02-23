// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IUniversalSigValidator {
    function isValidSig(address _signer, bytes32 _hash, bytes calldata _signature) external returns (bool);
}
