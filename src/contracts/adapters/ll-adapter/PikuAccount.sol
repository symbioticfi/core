// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {AsyncRedeemAccount} from "./AsyncRedeemAccount.sol";

import {IPikuAccount} from "../../../interfaces/adapters/ll-adapter/piku/IPikuAccount.sol";

/// @title PikuAccount
/// @notice Account for Piku Accountable ERC-7540 async redemption vaults.
contract PikuAccount is AsyncRedeemAccount, IPikuAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Piku account implementation.
    constructor(address asyncRedeemVault, address tokenToRedeem, address factory, address oracle)
        AsyncRedeemAccount(asyncRedeemVault, tokenToRedeem, tokenToRedeem, factory, oracle)
    {}
}
