// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {MigratablesFactory} from "src/contracts/common/MigratablesFactory.sol";

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";

contract VaultFactory is MigratablesFactory, IVaultFactory {
    constructor(address owner_) MigratablesFactory(owner_) {}
}
