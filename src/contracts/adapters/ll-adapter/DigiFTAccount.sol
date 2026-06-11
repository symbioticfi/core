// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {SettlementAccount, SettlementSubAccount} from "./common/SettlementAccount.sol";

import {IDigiFTAccount} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTAccount.sol";
import {IDigiFTSubRedManagement} from "../../../interfaces/adapters/ll-adapter/digift/IDigiFTSubRedManagement.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DigiFTAccount
/// @notice Account for DigiFT normal redemptions.
contract DigiFTAccount is SettlementAccount, IDigiFTAccount {
    /* IMMUTABLES */

    /// @inheritdoc IDigiFTAccount
    address public immutable SUB_RED_MANAGEMENT;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address subRedManagement,
        uint48 settlementDuration,
        address cowSwapSettlement
    ) SettlementAccount(oracle, factory, 0, tokenToRedeem, 0, 0, 0, settlementDuration, cowSwapSettlement) {
        SUB_RED_MANAGEMENT = subRedManagement;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Deploys a DigiFT request-holder subaccount.
    function _createSubAccount() internal override returns (address subAccount) {
        return address(new DigiFTSubAccount(_asset, address(this), TOKEN_TO_REDEEM, SUB_RED_MANAGEMENT));
    }
}

/// @title DigiFTSubAccount
/// @notice Request-holder subaccount for one DigiFT normal redemption.
contract DigiFTSubAccount is SettlementSubAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @dev DigiFT normal redemption manager.
    address internal immutable SUB_RED_MANAGEMENT;

    /* CONSTRUCTOR */

    /// @notice Creates the DigiFT request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem, address subRedManagement)
        SettlementSubAccount(asset, account, tokenToRedeem)
    {
        SUB_RED_MANAGEMENT = subRedManagement;
        IERC20(tokenToRedeem).forceApprove(subRedManagement, type(uint256).max);
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Submits held DigiFT tokens into a normal redemption.
    function _executeRedemption() internal override {
        IDigiFTSubRedManagement(SUB_RED_MANAGEMENT)
            .redeem(TOKEN_TO_REDEEM, ASSET, IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), block.timestamp);
    }
}
