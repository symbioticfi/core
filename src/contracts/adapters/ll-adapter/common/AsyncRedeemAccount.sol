// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CooldownAccount} from "./CooldownAccount.sol";

import {IAsyncRedeemAccount} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AsyncRedeemAccount
/// @notice Base account for ERC-7540 async redeem integrations.
abstract contract AsyncRedeemAccount is CooldownAccount, IAsyncRedeemAccount {
    /* STATE VARIABLES */

    /// @inheritdoc IAsyncRedeemAccount
    uint64[] public requestIds;
    /// @dev Whether an ERC-7540 redemption request id is tracked.
    mapping(uint256 requestId => bool exists) internal _requestIdExists;

    /* CONSTRUCTOR */

    /// @notice Creates the async redeem account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement, cowSwapVaultRelayer) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending async redemption request value in vault assets.
    function _totalAssets() internal view virtual override returns (uint256 assets) {
        address asyncRedeemVault = _asyncRedeemVault();

        for (uint256 i; i < requestIds.length; ++i) {
            uint256 requestId = requestIds[i];
            assets += IAsyncRedeemVault(asyncRedeemVault)
                .convertToAssets(
                    IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(requestId, address(this))
                        + IAsyncRedeemVault(asyncRedeemVault).claimableRedeemRequest(requestId, address(this))
                );
        }
    }

    /// @dev Claims processed requests and clears finished request ids.
    function _finalizeRequests() internal virtual override {
        address asyncRedeemVault = _asyncRedeemVault();

        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            uint256 trackedRequestId = requestIds[index];
            uint256 claimableShares =
                IAsyncRedeemVault(asyncRedeemVault).claimableRedeemRequest(trackedRequestId, address(this));
            if (claimableShares > 0) {
                IAsyncRedeemVault(asyncRedeemVault).redeem(claimableShares, address(this), address(this));
                claimableShares = 0;
            }

            if (
                IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(trackedRequestId, address(this)) == 0
                    && claimableShares == 0
            ) {
                _requestIdExists[trackedRequestId] = false;
                requestIds[index] = requestIds[requestIds.length - 1];
                requestIds.pop();
            }
        }
    }

    /// @dev Submits held token-to-redeem balance for async redemption.
    function _requestRedeem() internal virtual override {
        address asyncRedeemVault = _asyncRedeemVault();
        uint256 requestId = IAsyncRedeemVault(asyncRedeemVault)
            .requestRedeem(IERC20(asyncRedeemVault).balanceOf(address(this)), address(this), address(this));
        if (!_requestIdExists[requestId]) {
            _requestIdExists[requestId] = true;
            requestIds.push(uint64(requestId));
        }
    }

    /// @dev Returns the ERC-7540 async redeem vault.
    function _asyncRedeemVault() internal view virtual returns (address) {
        return TOKEN_TO_REDEEM;
    }
}
