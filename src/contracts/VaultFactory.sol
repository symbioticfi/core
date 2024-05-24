// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratablesFactory} from "src/contracts/base/MigratablesFactory.sol";

contract VaultFactory is MigratablesFactory {
    constructor(address owner_) MigratablesFactory(owner_) {}
}
