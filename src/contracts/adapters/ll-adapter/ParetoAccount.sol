// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IParetoAccount} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCreditVault} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoCreditVault.sol";
import {IParetoWithdrawalQueue} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoWithdrawalQueue.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ParetoAccount
/// @notice Account for Pareto epoch-queue redemptions.
contract ParetoAccount is Account, IParetoAccount {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IParetoAccount
    address public immutable WITHDRAWAL_QUEUE;

    /* STATE VARIABLES */

    /// @inheritdoc IParetoAccount
    uint256[] public queueEpochs;

    /* CONSTRUCTOR */

    /// @notice Creates the Pareto account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address withdrawalQueue,
        address cowSwapSettlement
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        WITHDRAWAL_QUEUE = withdrawalQueue;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the value of outstanding Pareto queue epochs in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 length = queueEpochs.length;
        uint256 unprocessedAmount;
        for (uint256 i; i < length; ++i) {
            uint256 epoch = queueEpochs[i];
            uint256 amount = IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).userWithdrawalsEpochs(address(this), epoch);
            uint256 price = IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).epochWithdrawPrice(epoch);
            if (price == 0) {
                unprocessedAmount += amount;
            } else {
                assets += amount.mulDiv(price, 1e18);
            }
        }
        assets += _tokenToRedeemToAssets(unprocessedAmount);
    }

    /// @dev Claims ready epochs, then queues all held Pareto tranche tokens.
    function _sync() internal override {
        uint256 length = queueEpochs.length;
        for (uint256 i = length; i > 0;) {
            uint256 epoch = queueEpochs[--i];
            if (IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).userWithdrawalsEpochs(address(this), epoch) != 0) {
                if (
                    IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).epochWithdrawPrice(epoch) == 0
                        || IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).epochPendingClaims(epoch) != 0
                ) {
                    continue;
                }
                IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).claimWithdrawRequest(epoch);
            }

            queueEpochs[i] = queueEpochs[--length];
            queueEpochs.pop();
        }

        uint256 balance = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        uint256 nextEpoch = IParetoCreditVault(IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).strategy()).epochNumber() + 1;
        if (IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).userWithdrawalsEpochs(address(this), nextEpoch) == 0) {
            queueEpochs.push(nextEpoch);
        }
        IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdraw(balance);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).underlying() != _asset) {
            revert InvalidAsset();
        }
        IERC20(TOKEN_TO_REDEEM).forceApprove(WITHDRAWAL_QUEUE, type(uint256).max);
    }
}
