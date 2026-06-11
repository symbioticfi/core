// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {SettlementAccount, SettlementSubAccount} from "./common/SettlementAccount.sol";

import {ISuperstateAccount} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateAccount.sol";
import {ISuperstateToken} from "../../../interfaces/adapters/ll-adapter/superstate/ISuperstateToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SuperstateAccount
/// @notice Account for Superstate off-chain settlement redemptions.
contract SuperstateAccount is SettlementAccount, ISuperstateAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Superstate account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        uint48 settlementDuration,
        address cowSwapSettlement
    ) SettlementAccount(oracle, factory, cooldown, tokenToRedeem, 0, 0, 0, settlementDuration, cowSwapSettlement) {}

    /* INTERNAL FUNCTIONS */

    /// @dev Deploys a Superstate request-holder subaccount.
    function _createSubAccount() internal override returns (address subAccount) {
        return address(new SuperstateSubAccount(_asset, address(this), TOKEN_TO_REDEEM));
    }
}

/// @title SuperstateSubAccount
/// @notice Request-holder subaccount for one Superstate off-chain redemption.
contract SuperstateSubAccount is SettlementSubAccount {
    /* CONSTRUCTOR */

    /// @notice Creates the Superstate request-holder subaccount.
    constructor(address asset, address account, address tokenToRedeem)
        SettlementSubAccount(asset, account, tokenToRedeem)
    {}

    /* INTERNAL FUNCTIONS */

    /// @dev Burns held Superstate tokens for off-chain settlement.
    function _executeRedemption() internal override {
        ISuperstateToken(TOKEN_TO_REDEEM).offchainRedeem(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)));
    }
}
