// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";

import {IOperatorRegistry} from "src/interfaces/IOperatorRegistry.sol";

contract OperatorRegistry is NonMigratablesRegistry, IOperatorRegistry {}
