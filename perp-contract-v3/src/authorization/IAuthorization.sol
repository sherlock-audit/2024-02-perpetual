// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

interface IAuthorization {
    function setAuthorization(address authorized, bool isAuthorized) external;

    function isAuthorized(address authorizer, address authorized) external returns (bool);
}
