// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratablesFactory} from "src/contracts/common/NonMigratablesFactory.sol";

import {IDelegatorFactory} from "src/interfaces/IDelegatorFactory.sol";

contract DelegatorFactory is NonMigratablesFactory, IDelegatorFactory {
    constructor(address owner_) NonMigratablesFactory(owner_) {}
}
