// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {MigratablesFactory} from "../common/MigratablesFactory.sol";

import {ILiquidLaneRegistry} from "../../interfaces/adapters/ILiquidLaneRegistry.sol";

/// @title LiquidLaneRegistry
/// @notice Migratable factory for liquidity lane adapters and token-specific account factory registry.
contract LiquidLaneRegistry is MigratablesFactory, ILiquidLaneRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc ILiquidLaneRegistry
    mapping(address tokenToRedeem => address factory) public accountFactories;

    /* CONSTRUCTOR */

    constructor(address newOwner) MigratablesFactory(newOwner) {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ILiquidLaneRegistry
    function setAccountFactory(address tokenToRedeem, address factory) public onlyOwner {
        accountFactories[tokenToRedeem] = factory;

        emit SetAccountFactory(tokenToRedeem, factory);
    }
}
