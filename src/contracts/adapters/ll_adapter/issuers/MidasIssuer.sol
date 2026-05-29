// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IMidasIssuer} from "../../../../interfaces/adapters/ll_adapter/issuers/IMidasIssuer.sol";
import {IMidasRedemptionVault} from "../../../../interfaces/adapters/ll_adapter/issuers/IMidasRedemptionVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MidasIssuer
/// @notice Issuer integration that submits Midas standard redemption requests.
contract MidasIssuer is IMidasIssuer {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IMidasIssuer
    address public immutable TOKEN_TO_REDEEM;
    /// @inheritdoc IMidasIssuer
    address public immutable ASSET;
    /// @inheritdoc IMidasIssuer
    address public immutable REDEMPTION_TOKEN;
    /// @inheritdoc IMidasIssuer
    address public immutable REDEMPTION_VAULT;

    /* CONSTRUCTOR */

    constructor(address tokenToRedeem, address asset, address redemptionToken, address redemptionVault) {
        TOKEN_TO_REDEEM = tokenToRedeem;
        ASSET = asset;
        REDEMPTION_TOKEN = redemptionToken;
        REDEMPTION_VAULT = redemptionVault;
    }

    /* PUBLIC FUNCTIONS */

    /// @inheritdoc IMidasIssuer
    function redeem() public returns (uint256 assets) {
        assets = totalAssets();
        if (assets == 0) {
            return 0;
        }

        address redemptionVault = REDEMPTION_VAULT;
        IERC20 tokenToRedeem = IERC20(TOKEN_TO_REDEEM);
        if (tokenToRedeem.allowance(address(this), redemptionVault) < assets) {
            tokenToRedeem.forceApprove(redemptionVault, type(uint256).max);
        }

        address asset = ASSET;
        (address dataFeed,,,) = IMidasRedemptionVault(redemptionVault).tokensConfig(asset);
        IMidasRedemptionVault(redemptionVault).redeemRequest(dataFeed == address(0) ? REDEMPTION_TOKEN : asset, assets);
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IMidasIssuer
    function totalAssets() public view returns (uint256) {
        return IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
    }
}
