// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {IParetoAccount} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoAccount.sol";
import {IParetoCDO} from "../../../interfaces/adapters/ll-adapter/pareto/IParetoCDO.sol";
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

    /// @inheritdoc IParetoAccount
    address public immutable REDEMPTION_TOKEN;

    /// @dev CDO that gates the queue's epoch state; fixed at queue initialization.
    address internal immutable IDLE_CDO;
    /// @dev Credit vault holding the epoch counter; fixed at queue initialization.
    address internal immutable STRATEGY;

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
        REDEMPTION_TOKEN = IParetoWithdrawalQueue(withdrawalQueue).underlying();
        IDLE_CDO = IParetoWithdrawalQueue(withdrawalQueue).idleCDOEpoch();
        STRATEGY = IParetoWithdrawalQueue(withdrawalQueue).strategy();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns outstanding Pareto withdrawal value and any held redemption token, in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 length = queueEpochs.length;
        uint256 unprocessedAmount;
        uint256 redemptionTokenAmount = IERC20(STRATEGY).balanceOf(address(this));
        for (uint256 i; i < length; ++i) {
            uint256 epoch = queueEpochs[i];
            uint256 amount = IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).userWithdrawalsEpochs(address(this), epoch);
            uint256 price = IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).epochWithdrawPrice(epoch);
            if (price == 0) {
                unprocessedAmount += amount;
            } else {
                redemptionTokenAmount += amount.mulDiv(price, 1e18);
            }
        }

        assets = _tokenToRedeemToAssets(unprocessedAmount);
        assets += REDEMPTION_TOKEN == _asset
            ? redemptionTokenAmount
            : _redemptionTokenToAssets(
                REDEMPTION_TOKEN, redemptionTokenAmount + IERC20(REDEMPTION_TOKEN).balanceOf(address(this))
            );
    }

    /// @dev Claims ready withdrawals, then submits all held Pareto tranche tokens.
    function _sync() internal override {
        if (IERC20(STRATEGY).balanceOf(address(this)) > 0) {
            try IParetoCDO(IDLE_CDO).claimWithdrawRequest() {} catch {}
            try IParetoCDO(IDLE_CDO).claimInstantWithdrawRequest() {} catch {}
        }

        uint256 length = queueEpochs.length;
        for (uint256 i = length; i > 0;) {
            uint256 epoch = queueEpochs[--i];
            if (IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).userWithdrawalsEpochs(address(this), epoch) > 0) {
                if (
                    IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).epochWithdrawPrice(epoch) == 0
                        || IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).epochPendingClaims(epoch) > 0
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
        if (IParetoCDO(IDLE_CDO).isEpochRunning()) {
            uint256 nextEpoch = IParetoCreditVault(STRATEGY).epochNumber() + 1;
            if (IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).userWithdrawalsEpochs(address(this), nextEpoch) == 0) {
                queueEpochs.push(nextEpoch);
            }
            IParetoWithdrawalQueue(WITHDRAWAL_QUEUE).requestWithdraw(balance);
        } else {
            IParetoCDO(IDLE_CDO).requestWithdraw(balance, TOKEN_TO_REDEEM);
        }
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault. The vault asset may differ from the Pareto
    ///      redemption token (e.g. a USDT vault redeeming Pareto's USDC underlying); the difference is
    ///      settled through the CoW converter, mirroring the async-redeem and Midas accounts.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        IERC20(TOKEN_TO_REDEEM).forceApprove(WITHDRAWAL_QUEUE, type(uint256).max);
        IERC20(TOKEN_TO_REDEEM).forceApprove(IDLE_CDO, type(uint256).max);
    }
}
