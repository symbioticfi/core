// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./CooldownAccount.sol";

import {IAsyncRedeemAccount} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {IERC7575Share} from "../../../../interfaces/adapters/ll-adapter/IERC7575Share.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AsyncRedeemAccount
/// @notice Base account for ERC-7540 async redeem integrations.
abstract contract AsyncRedeemAccount is CooldownAccount, IAsyncRedeemAccount {
    /* STATE VARIABLES */

    /// @inheritdoc IAsyncRedeemAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the async redeem account implementation.
    constructor(address oracle, address factory, uint48 cooldown, address tokenToRedeem, address cowSwapSettlement)
        CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending async redemption request value plus claimable value at fulfillment prices.
    function _totalAssets() internal view virtual override returns (uint256 assets) {
        address asyncRedeemVault = _asyncRedeemVault();
        for (uint256 i; i < requestIds.length; ++i) {
            assets += IAsyncRedeemVault(asyncRedeemVault)
                .convertToAssets(IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(requestIds[i], address(this)));
        }
        assets += IAsyncRedeemVault(asyncRedeemVault).maxWithdraw(address(this));
    }

    /// @dev Claims processed requests and clears finished request ids.
    function _finalizeRequests() internal virtual override {
        address asyncRedeemVault = _asyncRedeemVault();

        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            uint64 requestId = requestIds[index];
            uint256 claimableShares =
                IAsyncRedeemVault(asyncRedeemVault).claimableRedeemRequest(requestId, address(this));
            if (claimableShares > 0) {
                IAsyncRedeemVault(asyncRedeemVault).redeem(claimableShares, address(this), address(this));
            }

            if (IAsyncRedeemVault(asyncRedeemVault).pendingRedeemRequest(requestId, address(this)) == 0) {
                requestIds[index] = requestIds[requestIds.length - 1];
                requestIds.pop();
            }
        }
    }

    /// @dev Submits held token-to-redeem balance for async redemption.
    function _requestRedeem() internal virtual override returns (bool) {
        uint64 requestId = uint64(
            IAsyncRedeemVault(_asyncRedeemVault())
                .requestRedeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), address(this), address(this))
        );
        for (uint256 i; i < requestIds.length; ++i) {
            if (requestIds[i] == requestId) {
                return true;
            }
        }
        requestIds.push(requestId);
        return true;
    }

    /// @dev Returns the ERC-7540 async redeem vault.
    function _asyncRedeemVault() internal view virtual returns (address) {
        return IERC7575Share(TOKEN_TO_REDEEM).vault(_asset);
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] private __gap;
}
