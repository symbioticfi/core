// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IDigiFTAccount} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";
import {IDigiFTSubAccount} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTSubAccount.sol";
import {IDigiFTSubRedManagement} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTSubRedManagement.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DigiFTAccount
/// @notice Account for DigiFT normal redemptions.
contract DigiFTAccount is Account, IDigiFTAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IDigiFTAccount
    address public immutable SUB_RED_MANAGEMENT;
    /// @inheritdoc IDigiFTAccount
    uint48 public immutable PENDING_ASSETS_DURATION;

    /* STATE VARIABLES */

    /// @inheritdoc IDigiFTAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address subRedManagement,
        address cowSwapSettlement,
        uint48 pendingAssetsDuration
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        SUB_RED_MANAGEMENT = subRedManagement;
        PENDING_ASSETS_DURATION = pendingAssetsDuration;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns value pending in DigiFT redemption-request subaccounts.
    function _totalAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < subAccounts.length; ++i) {
            assets += IDigiFTSubAccount(subAccounts[i]).totalAssets();
        }
    }

    /// @dev Sweeps returned proceeds and initiates redemption through a new request-holder subaccount.
    function _sync() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;

            IDigiFTSubAccount(subAccounts[index]).sync();
            if (IDigiFTSubAccount(subAccounts[index]).totalAssets() == 0) {
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }

        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (amount > 0) {
            address subAccount = address(
                new DigiFTSubAccount(
                    _asset,
                    address(this),
                    TOKEN_TO_REDEEM,
                    _tokenToRedeemToAssets(amount),
                    SUB_RED_MANAGEMENT,
                    uint48(block.timestamp + PENDING_ASSETS_DURATION)
                )
            );

            subAccounts.push(subAccount);
            IERC20(TOKEN_TO_REDEEM).safeTransfer(subAccount, amount);
            IDigiFTSubAccount(subAccount).requestRedeem();
        }
    }
}

/// @title DigiFTSubAccount
/// @notice Request-holder subaccount for one DigiFT normal redemption.
contract DigiFTSubAccount is IDigiFTSubAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Vault asset expected from DigiFT redemption settlement.
    address internal immutable ASSET;
    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev DigiFT token submitted for redemption.
    address internal immutable TOKEN_TO_REDEEM;
    /// @dev DigiFT normal redemption manager.
    address internal immutable SUB_RED_MANAGEMENT;
    /// @dev Timestamp after which pending assets are no longer counted.
    uint48 internal immutable PENDING_ASSETS_DEADLINE;

    /* STATE VARIABLES */

    /// @dev Expected vault-asset value not yet swept to the parent account.
    uint256 internal _pendingAssets;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT request-holder subaccount.
    constructor(
        address asset,
        address account,
        address tokenToRedeem,
        uint256 pendingAssets_,
        address subRedManagement,
        uint48 pendingAssetsDeadline
    ) {
        ASSET = asset;
        ACCOUNT = account;
        TOKEN_TO_REDEEM = tokenToRedeem;
        _pendingAssets = pendingAssets_;
        SUB_RED_MANAGEMENT = subRedManagement;
        PENDING_ASSETS_DEADLINE = pendingAssetsDeadline;

        IERC20(TOKEN_TO_REDEEM).forceApprove(SUB_RED_MANAGEMENT, type(uint256).max);
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IDigiFTSubAccount
    function requestRedeem() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        IDigiFTSubRedManagement(SUB_RED_MANAGEMENT)
            .redeem(TOKEN_TO_REDEEM, ASSET, IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), block.timestamp);
    }

    /// @inheritdoc IDigiFTSubAccount
    function sync() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        uint256 assets = IERC20(ASSET).balanceOf(address(this));
        if (block.timestamp >= PENDING_ASSETS_DEADLINE) {
            _pendingAssets = 0;
        } else if (assets > 0) {
            _pendingAssets = _pendingAssets.saturatingSub(assets);
        }

        if (assets > 0) {
            IERC20(ASSET).safeTransfer(ACCOUNT, assets);
        }
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IDigiFTSubAccount
    function totalAssets() public view returns (uint256 assets) {
        assets = IERC20(ASSET).balanceOf(address(this));
        if (block.timestamp < PENDING_ASSETS_DEADLINE) {
            assets += _pendingAssets.saturatingSub(assets);
        }
    }
}
