// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {ISuperstateAccount} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateAccount.sol";
import {ISuperstateSubAccount} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateSubAccount.sol";
import {ISuperstateToken} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SuperstateAccount
/// @notice Account for Superstate off-chain settlement redemptions.
contract SuperstateAccount is CooldownAccount, ISuperstateAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ISuperstateAccount
    uint48 public immutable PENDING_ASSETS_DURATION;

    /* STATE VARIABLES */

    /// @inheritdoc ISuperstateAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the Superstate account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        uint48 pendingAssetsDuration,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        PENDING_ASSETS_DURATION = pendingAssetsDuration;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending Superstate request-holder value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < subAccounts.length; ++i) {
            assets += ISuperstateSubAccount(subAccounts[i]).totalAssets();
        }
    }

    /// @dev Sweeps returned proceeds and clears settled Superstate subaccounts.
    function _finalizeRequests() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;

            ISuperstateSubAccount(subAccounts[index]).sync();
            if (ISuperstateSubAccount(subAccounts[index]).isSettled()) {
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }
    }

    /// @dev Burns held Superstate tokens through a new request-holder subaccount.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        address subAccount = address(
            new SuperstateSubAccount(
                _asset,
                address(this),
                TOKEN_TO_REDEEM,
                uint48(block.timestamp) + PENDING_ASSETS_DURATION,
                _tokenToRedeemToAssets(amount)
            )
        );

        subAccounts.push(subAccount);
        IERC20(TOKEN_TO_REDEEM).safeTransfer(subAccount, amount);
        ISuperstateSubAccount(subAccount).requestRedeem();
    }
}

/// @title SuperstateSubAccount
/// @notice Request-holder subaccount for one Superstate off-chain redemption.
contract SuperstateSubAccount is ISuperstateSubAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Timestamp after which pending assets are no longer counted for valuation.
    uint48 internal immutable PENDING_ASSETS_DEADLINE;
    /// @dev Superstate token submitted for redemption.
    address internal immutable TOKEN_TO_REDEEM;
    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev Vault asset expected from settlement.
    address internal immutable ASSET;

    /* STATE VARIABLES */

    /// @dev Expected vault-asset value not yet swept to the parent account.
    uint256 internal _pendingAssets;

    /* CONSTRUCTOR */

    /// @notice Creates the Superstate request-holder subaccount.
    constructor(
        address asset,
        address account,
        address tokenToRedeem,
        uint48 pendingAssetsDeadline,
        uint256 pendingAssets
    ) {
        PENDING_ASSETS_DEADLINE = pendingAssetsDeadline;
        TOKEN_TO_REDEEM = tokenToRedeem;
        ACCOUNT = account;
        ASSET = asset;
        _pendingAssets = pendingAssets;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc ISuperstateSubAccount
    function requestRedeem() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        ISuperstateToken(TOKEN_TO_REDEEM).offchainRedeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
    }

    /// @inheritdoc ISuperstateSubAccount
    function sync() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        uint256 assets = IERC20(ASSET).balanceOf(address(this));
        if (assets > 0) {
            _pendingAssets = _pendingAssets.saturatingSub(assets);
            IERC20(ASSET).safeTransfer(ACCOUNT, assets);
        }
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc ISuperstateSubAccount
    function isSettled() public view returns (bool status) {
        return _pendingAssets == 0 && IERC20(ASSET).balanceOf(address(this)) == 0;
    }

    /// @inheritdoc ISuperstateSubAccount
    function totalAssets() public view returns (uint256 assets) {
        assets = IERC20(ASSET).balanceOf(address(this));
        if (block.timestamp < PENDING_ASSETS_DEADLINE) {
            assets += _pendingAssets.saturatingSub(assets);
        }
    }
}
