// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {Registry} from "./common/Registry.sol";

import {IAdapterRegistry} from "../interfaces/IAdapterRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AdapterRegistry
/// @notice Registry contract for whitelisted adapter contracts.
contract AdapterRegistry is Registry, Ownable, IAdapterRegistry {
    constructor(address initOwner) Ownable(initOwner) {}

    /// @inheritdoc IAdapterRegistry
    function whitelistAdapter(address adapter) external onlyOwner {
        if (isEntity(adapter)) {
            revert AdapterAlreadyWhitelisted();
        }

        _addEntity(adapter);
    }
}
