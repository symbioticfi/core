// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AdapterRegistry
/// @notice Registry contract for vault-scoped whitelisted adapter factories.
contract AdapterRegistry is Ownable, IAdapterRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IAdapterRegistry
    mapping(address vault => mapping(address adapter => bool status)) public isWhitelisted;

    /* CONSTRUCTOR */

    constructor(address newOwner) Ownable(newOwner) {}

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IAdapterRegistry
    function setWhitelistedStatus(address vault, address adapter, bool status) public onlyOwner {
        isWhitelisted[vault][adapter] = status;

        emit SetWhitelistedStatus(vault, adapter, status);
    }
}
