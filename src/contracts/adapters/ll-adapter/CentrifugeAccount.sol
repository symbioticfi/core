// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {AsyncRedeemAccount} from "./common/AsyncRedeemAccount.sol";

/// @title CentrifugeAccount
/// @notice Base account for Centrifuge ERC-7575 async redeem integrations.
abstract contract CentrifugeAccount is AsyncRedeemAccount {
    /// @notice Centrifuge ERC-7575 vault used for async redemptions.
    address public immutable ASYNC_REDEEM_VAULT;

    /* CONSTRUCTOR */

    /// @notice Creates the Centrifuge account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address redemptionToken,
        address asyncRedeemVault,
        address cowSwapSettlement
    ) AsyncRedeemAccount(oracle, factory, cooldown, tokenToRedeem, redemptionToken, cowSwapSettlement) {
        ASYNC_REDEEM_VAULT = asyncRedeemVault;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the configured Centrifuge ERC-7575 vault.
    function _asyncRedeemVault() internal view virtual override returns (address) {
        return ASYNC_REDEEM_VAULT;
    }
}
