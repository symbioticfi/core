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
    uint48 public immutable COOLDOWN;
    /// @inheritdoc IAsyncRedeemAccount
    address public immutable ASYNC_REDEEM_VAULT;

    /* STATE VARIABLES */

    /// @inheritdoc IAsyncRedeemAccount
    uint48 public lastRequestTimestamp;
    /// @dev ERC-7540 redemption request ids.
    uint256[] internal _requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the async redeem account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address asyncRedeemVault,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement, cowSwapVaultRelayer) {
        COOLDOWN = cooldown;
        ASYNC_REDEEM_VAULT = asyncRedeemVault;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending async redemption request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        IAsyncRedeemVault asyncRedeemVault = IAsyncRedeemVault(ASYNC_REDEEM_VAULT);

        for (uint256 i; i < _requestIds.length; ++i) {
            uint256 requestId = _requestIds[i];
            assets += asyncRedeemVault.convertToAssets(
                asyncRedeemVault.pendingRedeemRequest(requestId, address(this))
                    + asyncRedeemVault.claimableRedeemRequest(requestId, address(this))
            );
        }
    }

    /// @dev Claims processed requests and submits held token-to-redeem balance.
    function _sync() internal virtual override {
        IAsyncRedeemVault asyncRedeemVault = IAsyncRedeemVault(ASYNC_REDEEM_VAULT);

        for (uint256 i = _requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            uint256 trackedRequestId = _requestIds[index];
            uint256 claimableShares = asyncRedeemVault.claimableRedeemRequest(trackedRequestId, address(this));
            if (claimableShares > 0) {
                asyncRedeemVault.redeem(claimableShares, address(this), address(this));
            }

            if (
                asyncRedeemVault.pendingRedeemRequest(trackedRequestId, address(this)) == 0
                    && asyncRedeemVault.claimableRedeemRequest(trackedRequestId, address(this)) == 0
            ) {
                _requestIds[index] = _requestIds[_requestIds.length - 1];
                _requestIds.pop();
            }
        }

        if (msg.sender != owner() && lastRequestTimestamp > 0 && block.timestamp < lastRequestTimestamp + COOLDOWN) {
            return;
        }

        uint256 shares = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (shares == 0) {
            return;
        }

        uint256 newRequestId = asyncRedeemVault.requestRedeem(shares, address(this), address(this));
        for (uint256 i; i < _requestIds.length; ++i) {
            if (_requestIds[i] == newRequestId) {
                lastRequestTimestamp = uint48(block.timestamp);
                return;
            }
        }
        _requestIds.push(newRequestId);
        lastRequestTimestamp = uint48(block.timestamp);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);
        IERC20(TOKEN_TO_REDEEM).forceApprove(ASYNC_REDEEM_VAULT, type(uint256).max);
    }
}
