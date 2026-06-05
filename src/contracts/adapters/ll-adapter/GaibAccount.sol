// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IGaibAccount} from "../../../interfaces/adapters/ll-adapter/gaib/IGaibAccount.sol";
import {ISaid} from "../../../interfaces/adapters/ll-adapter/gaib/ISaid.sol";
import {IGaibSubAccount} from "../../../interfaces/adapters/ll-adapter/gaib/IGaibSubAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title GaibAccount
/// @notice Account for GAIB sAID queued unstaking.
contract GaibAccount is CooldownAccount, IGaibAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev AID asset received after unstaking.
    address internal immutable ASSET;

    /* STATE VARIABLES */

    /// @inheritdoc IGaibAccount
    address[] public subAccounts;

    /* CONSTRUCTOR */

    /// @notice Creates the GAIB account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement, cowSwapVaultRelayer) {
        ASSET = IERC4626(tokenToRedeem).asset();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending sAID unstake value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < subAccounts.length; ++i) {
            assets += _redemptionTokenToAssets(ASSET, IGaibSubAccount(subAccounts[i]).totalAssets());
        }
    }

    /// @dev Processes fulfilled unstake queue items.
    function _finalizeRequests() internal override {
        for (uint256 i = subAccounts.length; i > 0; --i) {
            uint256 index = i - 1;
            address subAccount = subAccounts[index];

            IGaibSubAccount(subAccount).sync();
            if (IGaibSubAccount(subAccount).totalAssets() == 0) {
                subAccounts[index] = subAccounts[subAccounts.length - 1];
                subAccounts.pop();
            }
        }
    }

    /// @dev Submits held sAID through a new request-holder subaccount.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        address subAccount = address(new GaibSubAccount(address(this), TOKEN_TO_REDEEM));

        subAccounts.push(subAccount);
        IERC20(TOKEN_TO_REDEEM).safeTransfer(subAccount, amount);
        IGaibSubAccount(subAccount).requestRedeem(amount);
    }
}

/// @title GaibSubAccount
/// @notice Request-holder subaccount for one GAIB unstake request.
contract GaibSubAccount is IGaibSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev Parent account that owns this subaccount.
    address internal immutable ACCOUNT;
    /// @dev GAIB sAID token submitted for unstaking.
    address internal immutable TOKEN_TO_REDEEM;
    /// @dev AID asset received after unstaking.
    address internal immutable ASSET;

    /* CONSTRUCTOR */

    /// @notice Creates the GAIB request-holder subaccount.
    constructor(address account, address tokenToRedeem) {
        ACCOUNT = account;
        TOKEN_TO_REDEEM = tokenToRedeem;
        ASSET = IERC4626(tokenToRedeem).asset();
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IGaibSubAccount
    function requestRedeem(uint256 amount) external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        ISaid(TOKEN_TO_REDEEM).unstake(amount);
    }

    /// @inheritdoc IGaibSubAccount
    function sync() external {
        if (msg.sender != ACCOUNT) {
            revert NotAccount();
        }

        try ISaid(TOKEN_TO_REDEEM).processUnstakeQueue(1) {} catch {}

        uint256 assets = IERC20(ASSET).balanceOf(address(this));
        if (assets > 0) {
            IERC20(ASSET).safeTransfer(ACCOUNT, assets);
        }
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IGaibSubAccount
    function totalAssets() public view returns (uint256 assets) {
        (, assets) = ISaid(TOKEN_TO_REDEEM).getUnstakeRequest(address(this));

        assets += IERC20(ASSET).balanceOf(address(this));
    }
}
