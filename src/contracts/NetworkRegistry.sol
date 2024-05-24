// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {INetworkRegistry} from "src/interfaces/INetworkRegistry.sol";

contract NetworkRegistry is NonMigratablesRegistry, INetworkRegistry {}
