// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "./Account.sol";

import {IAsyncRedeemAccount} from "../../../interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../../interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AsyncRedeemAccount
/// @notice Base account for ERC-7540 async redeem integrations.
abstract contract AsyncRedeemAccount is Account, IAsyncRedeemAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IAsyncRedeemAccount
    address public immutable ASYNC_REDEEM_VAULT;
    /// @inheritdoc IAsyncRedeemAccount
    address public immutable REDEEM_SHARE;

    /* STATE VARIABLES */

    /// @dev ERC-7540 redemption request ids.
    uint256[] internal _requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the async redeem account implementation.
    constructor(address asyncRedeemVault, address tokenToRedeem, address redeemShare, address factory, address oracle)
        Account(factory, oracle, tokenToRedeem)
    {
        REDEEM_SHARE = redeemShare;
        ASYNC_REDEEM_VAULT = asyncRedeemVault;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns held redeem-share value plus pending async redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        IAsyncRedeemVault asyncRedeemVault = IAsyncRedeemVault(ASYNC_REDEEM_VAULT);
        address redeemShare = REDEEM_SHARE;

        if (redeemShare != _asset && redeemShare != TOKEN_TO_REDEEM) {
            assets += asyncRedeemVault.convertToAssets(IERC20(redeemShare).balanceOf(address(this)));
        }

        for (uint256 i; i < _requestIds.length; ++i) {
            uint256 requestId = _requestIds[i];
            assets += asyncRedeemVault.convertToAssets(
                asyncRedeemVault.pendingRedeemRequest(requestId, address(this))
                    + asyncRedeemVault.claimableRedeemRequest(requestId, address(this))
            );
        }
    }

    /// @dev Claims processed requests, prepares provider-specific shares, and submits held redeem shares.
    function _sync() internal override {
        _claimRedeemRequests();
        _beforeRequestRedeem();
        _requestRedeem();
    }

    /// @dev Hook for provider-specific conversion before submitting redeem shares.
    function _beforeRequestRedeem() internal virtual {}

    /// @dev Submits held redeem shares to the async redeem vault.
    function _requestRedeem() internal {
        uint256 shares = IERC20(REDEEM_SHARE).balanceOf(address(this));
        if (shares == 0) {
            return;
        }

        uint256 requestId = IAsyncRedeemVault(ASYNC_REDEEM_VAULT).requestRedeem(shares, address(this), address(this));
        _addRequestId(requestId);
    }

    /// @dev Claims all currently claimable redemption shares and prunes completed request ids.
    function _claimRedeemRequests() internal {
        IAsyncRedeemVault asyncRedeemVault = IAsyncRedeemVault(ASYNC_REDEEM_VAULT);

        for (uint256 i = _requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            uint256 requestId = _requestIds[index];
            uint256 claimableShares = asyncRedeemVault.claimableRedeemRequest(requestId, address(this));
            if (claimableShares > 0) {
                asyncRedeemVault.redeem(claimableShares, address(this), address(this));
            }

            if (
                asyncRedeemVault.pendingRedeemRequest(requestId, address(this)) == 0
                    && asyncRedeemVault.claimableRedeemRequest(requestId, address(this)) == 0
            ) {
                _requestIds[index] = _requestIds[_requestIds.length - 1];
                _requestIds.pop();
            }
        }
    }

    /// @dev Adds the request id once, preserving aggregated request id zero semantics.
    function _addRequestId(uint256 requestId) internal {
        for (uint256 i; i < _requestIds.length; ++i) {
            if (_requestIds[i] == requestId) {
                return;
            }
        }
        _requestIds.push(requestId);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);
        IERC20(REDEEM_SHARE).forceApprove(ASYNC_REDEEM_VAULT, type(uint256).max);
    }
}
