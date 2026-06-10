// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {ISecuritizeAccount} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeAccount.sol";
import {ISecuritizeSubAccount} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeSubAccount.sol";
import {ISecuritizeToken} from "../../../interfaces/adapters/ll-adapter/securitize/ISecuritizeToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecuritizeAccount
/// @notice Account for Securitize off-chain settlement redemptions.
contract SecuritizeAccount is CooldownAccount, ISecuritizeAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc ISecuritizeAccount
    uint48 public immutable PENDING_ASSETS_DURATION;

    /* STATE VARIABLES */

    /// @inheritdoc ISecuritizeAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the Securitize account implementation.
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

    /// @dev Returns pending Securitize request-holder value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < subAccounts.length; ++i) {
            assets += ISecuritizeSubAccount(subAccounts[i]).totalAssets();
        }
    }

    /// @dev Sweeps returned proceeds and clears settled Securitize subaccounts.
    function _finalizeRequests() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;

            ISecuritizeSubAccount(subAccounts[index]).sync();
            if (ISecuritizeSubAccount(subAccounts[index]).isSettled()) {
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }
    }

    /// @dev Burns held Securitize tokens through a new request-holder subaccount.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        address subAccount = address(
            new SecuritizeSubAccount(
                _asset,
                address(this),
                TOKEN_TO_REDEEM,
                uint48(block.timestamp) + PENDING_ASSETS_DURATION,
                _tokenToRedeemToAssets(amount)
            )
        );

        subAccounts.push(subAccount);
        IERC20(TOKEN_TO_REDEEM).safeTransfer(subAccount, amount);
        ISecuritizeSubAccount(subAccount).requestRedeem();
    }
}

/// @title SecuritizeSubAccount
/// @notice Request-holder subaccount for one Securitize off-chain redemption.
contract SecuritizeSubAccount is ISecuritizeSubAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @dev Timestamp after which pending assets are no longer counted for valuation.
    uint48 internal immutable PENDING_ASSETS_DEADLINE;
    /// @dev Securitize token submitted for redemption.
    address internal immutable TOKEN_TO_REDEEM;
    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev Vault asset expected from settlement.
    address internal immutable ASSET;

    /* STATE VARIABLES */

    /// @dev Expected vault-asset value not yet swept to the parent account.
    uint256 internal _pendingAssets;

    /* CONSTRUCTOR */

    /// @notice Creates the Securitize request-holder subaccount.
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

    /// @inheritdoc ISecuritizeSubAccount
    function requestRedeem() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        ISecuritizeToken(TOKEN_TO_REDEEM).burn(address(this), IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), "");
    }

    /// @inheritdoc ISecuritizeSubAccount
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

    /// @inheritdoc ISecuritizeSubAccount
    function isSettled() public view returns (bool status) {
        return _pendingAssets == 0 && IERC20(ASSET).balanceOf(address(this)) == 0;
    }

    /// @inheritdoc ISecuritizeSubAccount
    function totalAssets() public view returns (uint256 assets) {
        assets = IERC20(ASSET).balanceOf(address(this));
        if (block.timestamp < PENDING_ASSETS_DEADLINE) {
            assets += _pendingAssets.saturatingSub(assets);
        }
    }
}
