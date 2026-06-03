// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {ILiquidLaneRegistry} from "../../interfaces/adapters/ILiquidLaneRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LiquidLaneRegistry
/// @notice Owned registry for token-specific liquidity lane account factories.
contract LiquidLaneRegistry is Ownable, ILiquidLaneRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc ILiquidLaneRegistry
    mapping(address tokenToRedeem => address factory) public accountFactories;

    /* CONSTRUCTOR */

    constructor(address newOwner) Ownable(newOwner) {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc ILiquidLaneRegistry
    function setAccountFactory(address tokenToRedeem, address factory) public onlyOwner {
        if (tokenToRedeem == address(0) || factory == address(0)) {
            revert InvalidConfiguration();
        }

        accountFactories[tokenToRedeem] = factory;

        emit SetAccountFactory(tokenToRedeem, factory);
    }
}
