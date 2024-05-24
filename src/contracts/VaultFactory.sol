// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MigratablesFactory} from "src/contracts/base/MigratablesFactory.sol";

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";

contract VaultFactory is MigratablesFactory, IVaultFactory {
    constructor(address owner_) MigratablesFactory(owner_) {}
}
