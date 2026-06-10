// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IParetoAccount} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ParetoAccount
/// @notice Account for Pareto credit-vault tranche redemptions.
contract ParetoAccount is CooldownAccount, IParetoAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc IParetoAccount
    address public immutable IDLE_CDO;
    /// @inheritdoc IParetoAccount
    address public immutable RECEIPT_TOKEN;

    /* CONSTRUCTOR */

    /// @notice Creates the Pareto account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address idleCdo,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        IDLE_CDO = idleCdo;
        RECEIPT_TOKEN = IParetoCDO(idleCdo).strategy();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Values held Pareto tranche tokens through the credit-vault virtual price.
    function _tokenToRedeemToAssets(uint256 amount) internal view override returns (uint256) {
        address idleCdo = IDLE_CDO;
        return _redemptionTokenToAssets(
            IParetoCDO(idleCdo).token(),
            amount.mulDiv(
                IParetoCDO(idleCdo).virtualPrice(TOKEN_TO_REDEEM), 10 ** IERC20Metadata(TOKEN_TO_REDEEM).decimals()
            )
        );
    }

    /// @dev Returns pending Pareto withdrawal receipt value in vault assets.
    function _totalAssets() internal view override returns (uint256) {
        return _redemptionTokenToAssets(IParetoCDO(IDLE_CDO).token(), IERC20(RECEIPT_TOKEN).balanceOf(address(this)));
    }

    /// @dev Claims eligible Pareto withdrawal requests.
    function _finalizeRequests() internal override {
        try IParetoCDO(IDLE_CDO).claimWithdrawRequest() {} catch {}
    }

    /// @dev Submits held tranche tokens into a Pareto withdrawal request.
    function _requestRedeem() internal override {
        IParetoCDO(IDLE_CDO).requestWithdraw(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), TOKEN_TO_REDEEM);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (IParetoCDO(IDLE_CDO).token() != _asset) {
            revert InvalidAsset();
        }
        IERC20(TOKEN_TO_REDEEM).forceApprove(IDLE_CDO, type(uint256).max);
    }
}
