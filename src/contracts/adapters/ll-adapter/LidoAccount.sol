// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {ILidoAccount} from "../../../interfaces/adapters/ll-adapter/lido/ILidoAccount.sol";
import {ILidoWithdrawalQueue} from "../../../interfaces/adapters/ll-adapter/lido/ILidoWithdrawalQueue.sol";
import {IWETH} from "../../../interfaces/adapters/ll-adapter/etherfi/IWETH.sol";
import {IWstETH} from "../../../interfaces/adapters/ll-adapter/lido/IWstETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LidoAccount
/// @notice Account for Lido wstETH redemptions.
contract LidoAccount is Account, ILidoAccount {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* IMMUTABLES */

    /// @inheritdoc ILidoAccount
    address public immutable WITHDRAWAL_QUEUE;
    /// @inheritdoc ILidoAccount
    address public immutable WSTETH;
    /// @inheritdoc ILidoAccount
    address public immutable STETH;

    /* STATE VARIABLES */

    /// @inheritdoc ILidoAccount
    uint256 public pendingAssets;
    /// @inheritdoc ILidoAccount
    uint64[] public requestIds;

    /* CONSTRUCTOR */

    /// @notice Creates the Lido account implementation.
    constructor(
        address stETH,
        address oracle,
        address wstETH,
        address factory,
        address withdrawalQueue,
        address cowSwapSettlement,
        address cowSwapVaultRelayer
    ) Account(oracle, factory, wstETH, cowSwapSettlement, cowSwapVaultRelayer) {
        WITHDRAWAL_QUEUE = withdrawalQueue;
        WSTETH = wstETH;
        STETH = stETH;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns held stETH value plus pending request value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        assets = pendingAssets;

        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance > 0) {
            assets += _tokenToRedeemToAssets(IWstETH(WSTETH).getWstETHByStETH(stETHBalance));
        }
    }

    /// @dev Claims finalized withdrawals and submits held wstETH or stETH inventory.
    function _sync() internal override {
        for (uint256 i = requestIds.length; i > 0; --i) {
            uint256 ethBalanceBefore = address(this).balance;
            try ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawal(requestIds[i - 1]) {
                uint256 claimed = address(this).balance - ethBalanceBefore;
                if (claimed > 0) {
                    IWETH(_asset).deposit{value: claimed}();
                    uint256 claimedAssets = claimed.mulDiv(_unit, 1e18);
                    pendingAssets = pendingAssets > claimedAssets ? pendingAssets - claimedAssets : 0;
                    requestIds[i - 1] = requestIds[requestIds.length - 1];
                    requestIds.pop();
                }
            } catch {}
        }

        uint256 amountToRedeem = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        uint256 minStETHAmount = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 maxStETHAmount = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE).MAX_STETH_WITHDRAWAL_AMOUNT();
        if (amountToRedeem > 0 && IWstETH(WSTETH).getStETHByWstETH(amountToRedeem) >= minStETHAmount) {
            uint256 maxWstETHAmount = IWstETH(WSTETH).getWstETHByStETH(maxStETHAmount);
            uint256[] memory ids = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE)
                .requestWithdrawalsWstETH(_splitAmounts(amountToRedeem, maxWstETHAmount), address(this));
            for (uint256 i; i < ids.length; ++i) {
                requestIds.push(uint64(ids[i]));
            }
            pendingAssets += _tokenToRedeemToAssets(amountToRedeem);
        }

        uint256 stETHBalance = IERC20(STETH).balanceOf(address(this));
        if (stETHBalance >= minStETHAmount) {
            uint256[] memory ids = ILidoWithdrawalQueue(WITHDRAWAL_QUEUE)
                .requestWithdrawals(_splitAmounts(stETHBalance, maxStETHAmount), address(this));
            for (uint256 i; i < ids.length; ++i) {
                requestIds.push(uint64(ids[i]));
            }
            pendingAssets += _tokenToRedeemToAssets(IWstETH(WSTETH).getWstETHByStETH(stETHBalance));
        }
    }

    /// @dev Splits an amount into Lido queue-sized requests.
    function _splitAmounts(uint256 amount, uint256 maxAmount) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](amount.ceilDiv(maxAmount));
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = amount > maxAmount ? maxAmount : amount;
            amount -= amounts[i];
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address owner_, bytes memory data) internal override {
        super._initialize(initialVersion, owner_, data);

        IERC20(WSTETH).forceApprove(WITHDRAWAL_QUEUE, type(uint256).max);
        IERC20(STETH).forceApprove(WITHDRAWAL_QUEUE, type(uint256).max);
    }

    /* RECEIVE */

    receive() external payable {}
}
