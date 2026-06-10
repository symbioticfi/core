// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {INoonAccount} from "../../../interfaces/adapters/ll-adapter/noon/INoonAccount.sol";
import {INoonWithdrawalHandler} from "../../../interfaces/adapters/ll-adapter/noon/INoonWithdrawalHandler.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title NoonAccount
/// @notice Account for Noon sUSN withdrawal-handler redemptions.
contract NoonAccount is CooldownAccount, INoonAccount {
    /* IMMUTABLES */

    /// @inheritdoc INoonAccount
    address public immutable WITHDRAWAL_HANDLER;

    /* STATE VARIABLES */

    /// @inheritdoc INoonAccount
    uint256[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Noon account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address withdrawalHandler,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        WITHDRAWAL_HANDLER = withdrawalHandler;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending Noon withdrawal request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        address withdrawalHandler = WITHDRAWAL_HANDLER;

        for (uint256 i; i < requestIds.length; ++i) {
            INoonWithdrawalHandler.WithdrawalRequest memory request =
                INoonWithdrawalHandler(withdrawalHandler).getWithdrawalRequest(address(this), requestIds[i]);
            if (!request.claimed) {
                assets += _redemptionTokenToAssets(INoonWithdrawalHandler(withdrawalHandler).usn(), request.amount);
            }
        }
    }

    /// @dev Claims matured Noon withdrawal requests and clears claimed request ids.
    function _finalizeRequests() internal override {
        address withdrawalHandler = WITHDRAWAL_HANDLER;

        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 index = i - 1;
            INoonWithdrawalHandler.WithdrawalRequest memory request =
                INoonWithdrawalHandler(withdrawalHandler).getWithdrawalRequest(address(this), requestIds[index]);

            if (!request.claimed) {
                try INoonWithdrawalHandler(withdrawalHandler).claimWithdrawal(requestIds[index]) {}
                catch {
                    continue;
                }
            }

            requestIds[index] = requestIds[requestIds.length - 1];
            requestIds.pop();
        }
    }

    /// @dev Submits held sUSN into a Noon withdrawal request.
    function _requestRedeem() internal override {
        requestIds.push(INoonWithdrawalHandler(WITHDRAWAL_HANDLER).getUserNextRequestId(address(this)));
        IERC4626(TOKEN_TO_REDEEM)
            .redeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), WITHDRAWAL_HANDLER, address(this));
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (INoonWithdrawalHandler(WITHDRAWAL_HANDLER).usn() != _asset) {
            revert InvalidAsset();
        }
    }
}
