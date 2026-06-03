// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {IAccountRegistry} from "../../../interfaces/adapters/ll-adapter/IAccountRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AccountRegistry
/// @notice Owned registry for token-specific liquidity lane account factories.
contract AccountRegistry is Ownable, IAccountRegistry {
    /* STATE VARIABLES */

    /// @inheritdoc IAccountRegistry
    mapping(address tokenToRedeem => address factory) public accountFactories;

    /* CONSTRUCTOR */

    constructor(address newOwner) Ownable(newOwner) {}

    /* PUBLIC FUNCTIONS (OWNER) */

    /// @inheritdoc IAccountRegistry
    function setAccountFactory(address tokenToRedeem, address factory) public onlyOwner {
        if (tokenToRedeem == address(0) || factory == address(0)) {
            revert InvalidConfiguration();
        }

        accountFactories[tokenToRedeem] = factory;

        emit SetAccountFactory(tokenToRedeem, factory);
    }
}
