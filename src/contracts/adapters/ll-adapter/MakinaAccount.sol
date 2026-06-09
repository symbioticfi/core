// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IMakinaAccount} from "../../../interfaces/adapters/ll-adapter/makina/IMakinaAccount.sol";
import {IMakinaMachine} from "../../../interfaces/adapters/ll-adapter/makina/IMakinaMachine.sol";
import {IMakinaRedeemer} from "../../../interfaces/adapters/ll-adapter/makina/IMakinaRedeemer.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MakinaAccount
/// @notice Account for Makina async redeemer receipt redemptions.
contract MakinaAccount is CooldownAccount, IMakinaAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMakinaAccount
    address public immutable REDEEMER;

    /// @dev Makina Machine accounting token received after finalized claims.
    address internal immutable _accountingToken;

    /* STATE VARIABLES */

    /// @inheritdoc IMakinaAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Makina account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address redeemer,
        address tokenToRedeem,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        REDEEMER = redeemer;
        _accountingToken = IMakinaMachine(IMakinaRedeemer(redeemer).machine()).accountingToken();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending and finalized Makina redemption receipt value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        for (uint256 i; i < requestIds.length; ++i) {
            uint256 requestId = requestIds[i];
            try IMakinaRedeemer(REDEEMER).getClaimableAssets(requestId) returns (uint256 claimableAssets) {
                assets += _redemptionTokenToAssets(_accountingToken, claimableAssets);
            } catch {
                try IMakinaRedeemer(REDEEMER).getShares(requestId) returns (uint256 shares) {
                    assets += _tokenToRedeemToAssets(shares);
                } catch {}
            }
        }
    }

    /// @dev Claims finalized Makina receipts and clears their request ids.
    function _finalizeRequests() internal override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 index = i - 1;

            try IMakinaRedeemer(REDEEMER).claimAssets(requestIds[index]) returns (uint256) {
                requestIds[index] = requestIds[requestIds.length - 1];
                requestIds.pop();
            } catch {}
        }
    }

    /// @dev Submits held token-to-redeem balance to the Makina redeemer.
    function _requestRedeem() internal override {
        requestIds.push(
            uint64(
                IMakinaRedeemer(REDEEMER)
                    .requestRedeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), address(this), 0)
            )
        );
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (_accountingToken != _asset) {
            revert InvalidAsset();
        }
        IERC20(TOKEN_TO_REDEEM).forceApprove(REDEEMER, type(uint256).max);
    }
}
