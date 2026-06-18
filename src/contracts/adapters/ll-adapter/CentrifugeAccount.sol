// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AsyncRedeemAccount} from "./common/AsyncRedeemAccount.sol";

/// @title CentrifugeAccount
/// @notice Base account for Centrifuge ERC-7575 async redeem integrations.
abstract contract CentrifugeAccount is AsyncRedeemAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Centrifuge account implementation.
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address cowSwapSettlement)
        AsyncRedeemAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
    {}
}
