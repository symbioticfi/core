// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {AsyncRedeemAccount} from "./AsyncRedeemAccount.sol";

import {ICentrifugeAccount} from "../../../interfaces/adapters/ll-adapter/centrifuge/ICentrifugeAccount.sol";

/// @title CentrifugeAccount
/// @notice Account for Centrifuge ERC-7540 async redemption vaults.
contract CentrifugeAccount is AsyncRedeemAccount, ICentrifugeAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Centrifuge account implementation.
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address asyncRedeemVault)
        AsyncRedeemAccount(oracle, factory, cooldown, tokenToRedeem, asyncRedeemVault)
    {}
}
