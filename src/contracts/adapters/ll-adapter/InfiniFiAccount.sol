// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IInfiniFiAccount} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiAccount.sol";
import {IInfiniFiGateway} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiGateway.sol";
import {
    IInfiniFiRedeemController
} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiRedeemController.sol";
import {IInfiniFiUnwindingModule} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiUnwindingModule.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title InfiniFiAccount
/// @notice Account for infiniFi locked iUSD (liUSD) unwinding redemptions.
/// @dev Valuation is live everywhere by design: unwinding positions keep earning and slashing is
///      reflected through the unwinding module's live balances, while held, queued and claimable
///      iUSD is valued at par like the protocol's fixed $1 oracle does.
contract InfiniFiAccount is CooldownAccount, IInfiniFiAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IInfiniFiAccount
    address public immutable GATEWAY;
    /// @inheritdoc IInfiniFiAccount
    address public immutable UNWINDING_MODULE;
    /// @inheritdoc IInfiniFiAccount
    address public immutable REDEEM_CONTROLLER;
    /// @inheritdoc IInfiniFiAccount
    address public immutable IUSD;
    /// @inheritdoc IInfiniFiAccount
    uint32 public immutable UNWINDING_EPOCHS;

    /* STATE VARIABLES */

    /// @inheritdoc IInfiniFiAccount
    uint48[] public unwindingTimestamps;

    /// @inheritdoc IInfiniFiAccount
    RedemptionTicket[] public redemptionTickets;

    /* CONSTRUCTOR */

    /// @notice Creates the infiniFi account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address gateway,
        address unwindingModule,
        address redeemController,
        address iusd,
        uint32 unwindingEpochs,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        GATEWAY = gateway;
        UNWINDING_MODULE = unwindingModule;
        REDEEM_CONTROLLER = redeemController;
        IUSD = iusd;
        UNWINDING_EPOCHS = unwindingEpochs;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending unwinding, held iUSD, queued redemption and claimable value in vault assets.
    ///      Queued tickets are valued at par until the redeem controller's queue cursor passes them;
    ///      funded tickets are valued through their pending claims instead, so a front-of-queue ticket
    ///      funded partially is transiently counted at par on top of its partial claim until popped.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 receiptAmount = IERC20(IUSD).balanceOf(address(this));

        for (uint256 i; i < unwindingTimestamps.length; ++i) {
            receiptAmount += IInfiniFiUnwindingModule(UNWINDING_MODULE).balanceOf(address(this), unwindingTimestamps[i]);
        }

        (uint128 queueBegin,) = IInfiniFiRedeemController(REDEEM_CONTROLLER).queue();
        for (uint256 i; i < redemptionTickets.length; ++i) {
            if (redemptionTickets[i].queueIndex >= queueBegin) {
                receiptAmount += redemptionTickets[i].amount;
            }
        }

        if (receiptAmount > 0) {
            assets += _redemptionTokenToAssets(IUSD, receiptAmount);
        }
        assets += IInfiniFiRedeemController(REDEEM_CONTROLLER).userPendingClaims(address(this));
    }

    /// @dev Completes matured unwindings, redeems held iUSD and claims funded queue tickets.
    ///      The gateway reverts withdrawals and redemptions for immature positions and while protocol
    ///      losses are unaccrued, so both calls are try/catch-tolerated and retried on later syncs.
    function _finalizeRequests() internal override {
        for (uint256 i = unwindingTimestamps.length; i > 0; --i) {
            uint256 index = i - 1;

            try IInfiniFiGateway(GATEWAY).withdraw(unwindingTimestamps[index]) {
                unwindingTimestamps[index] = unwindingTimestamps[unwindingTimestamps.length - 1];
                unwindingTimestamps.pop();
            } catch {}
        }

        uint256 receiptAmount = IERC20(IUSD).balanceOf(address(this));
        if (receiptAmount > 0) {
            (, uint128 queueEnd) = IInfiniFiRedeemController(REDEEM_CONTROLLER).queue();
            uint256 enqueuedBefore = IInfiniFiRedeemController(REDEEM_CONTROLLER).totalEnqueuedRedemptions();

            // minAssetsOut is 0: every redeem path prices atomically at the protocol oracle rate, the
            // queue path returns 0 assets out by design and pays at the funding-time rate regardless
            try IInfiniFiGateway(GATEWAY).redeem(address(this), receiptAmount, 0) {
                // assumes redeem never decreases totalEnqueuedRedemptions in-call (a violation reverts via underflow)
                uint256 enqueued =
                    IInfiniFiRedeemController(REDEEM_CONTROLLER).totalEnqueuedRedemptions() - enqueuedBefore;
                if (enqueued > 0) {
                    redemptionTickets.push(RedemptionTicket({queueIndex: queueEnd, amount: enqueued}));
                }
            } catch {}
        }

        (uint128 queueBegin,) = IInfiniFiRedeemController(REDEEM_CONTROLLER).queue();
        for (uint256 i = redemptionTickets.length; i > 0; --i) {
            uint256 index = i - 1;

            if (redemptionTickets[index].queueIndex < queueBegin) {
                redemptionTickets[index] = redemptionTickets[redemptionTickets.length - 1];
                redemptionTickets.pop();
            }
        }

        if (IInfiniFiRedeemController(REDEEM_CONTROLLER).userPendingClaims(address(this)) > 0) {
            try IInfiniFiGateway(GATEWAY).claimRedemption() {} catch {}
        }
    }

    /// @dev Starts unwinding the held liUSD balance. Unwinding positions are keyed by
    ///      keccak(account, block.timestamp), so a second request in the same second would collide
    ///      and revert: lastRequestTimestamp equals block.timestamp only when a request already
    ///      happened this second, so it is skipped and the balance is picked up by a later sync.
    function _requestRedeem() internal override {
        if (lastRequestTimestamp == block.timestamp) {
            return;
        }

        IInfiniFiGateway(GATEWAY).startUnwinding(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), UNWINDING_EPOCHS);
        unwindingTimestamps.push(uint48(block.timestamp));
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        if (IInfiniFiRedeemController(REDEEM_CONTROLLER).assetToken() != _asset) {
            revert InvalidAsset();
        }
        IERC20(TOKEN_TO_REDEEM).forceApprove(GATEWAY, type(uint256).max);
        IERC20(IUSD).forceApprove(GATEWAY, type(uint256).max);
    }
}
