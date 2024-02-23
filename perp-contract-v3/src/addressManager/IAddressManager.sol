// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IAddressManager {
    function getAddress(string memory _name) external view returns (address);
}
