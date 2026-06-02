// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.35;

import {Account} from "../accounts/Account.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ACRED_Account
/// @notice Centrifuge/Securitize account for ACRED redemptions.
contract ACRED_Account is Account {
    using SafeERC20 for IERC20;

    address public immutable REDEMPTION_WALLET;

    uint48 public constant POINT_0 = 1_777_593_599;
    uint48 public constant POINT_1 = 1_785_542_399;
    uint48 public constant POINT_2 = 1_793_404_799;
    uint48 public constant POINT_3 = 1_801_267_199;

    constructor(address factory, address oracle, address tokenToRedeem, address redemptionWallet)
        Account(factory, oracle, tokenToRedeem)
    {
        REDEMPTION_WALLET = redemptionWallet;
    }

    function _requestRedeem(uint256 amountToRedeem, uint256) internal override {
        IERC20(TOKEN_TO_REDEEM).safeTransfer(REDEMPTION_WALLET, amountToRedeem);
    }
}
