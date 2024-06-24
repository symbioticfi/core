// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratablesFactory} from "src/contracts/common/NonMigratablesFactory.sol";

import {ISlasherFactory} from "src/interfaces/ISlasherFactory.sol";

contract SlasherFactory is NonMigratablesFactory, ISlasherFactory {
    constructor(address owner_) NonMigratablesFactory(owner_) {}
}
