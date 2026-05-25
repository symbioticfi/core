// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AdapterRegistry
/// @notice Registry contract for whitelisted adapter factories.
contract AdapterRegistry is Ownable, IAdapterRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IAdapterRegistry
    mapping(address adapter => bool) public globalIsWhitelisted;
    /// @inheritdoc IAdapterRegistry
    mapping(address vault => mapping(address adapter => bool)) public vaultIsWhitelisted;

    /* CONSTRUCTOR */

    constructor(address curOwner) Ownable(curOwner) {}

    /* EXTERNAL FUNCTIONS */

    /// @inheritdoc IAdapterRegistry
    function setGlobalWhitelistStatus(address adapter, bool status) external onlyOwner {
        globalIsWhitelisted[adapter] = status;

        emit SetGlobalWhitelistStatus(adapter, status);
    }

    /// @inheritdoc IAdapterRegistry
    function setVaultWhitelistStatus(address vault, address adapter, bool status) external onlyOwner {
        vaultIsWhitelisted[vault][adapter] = status;

        emit SetVaultWhitelistStatus(vault, adapter, status);
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IAdapterRegistry
    function isWhitelisted(address vault, address adapter) external view returns (bool status) {
        return globalIsWhitelisted[adapter] || vaultIsWhitelisted[vault][adapter];
    }
}
