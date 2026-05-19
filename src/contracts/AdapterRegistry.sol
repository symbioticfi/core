// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Registry} from "./common/Registry.sol";

import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title AdapterRegistry
/// @notice Registry contract for whitelisted adapter contracts.
contract AdapterRegistry is Registry, OwnableUpgradeable, IAdapterRegistry {
    /// @dev Initializes the contract with the given owner.
    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
    }

    /// @inheritdoc IAdapterRegistry
    function whitelistAdapter(address adapter) external onlyOwner {
        if (isEntity(adapter)) {
            revert AdapterAlreadyWhitelisted();
        }

        _addEntity(adapter);
    }
}
