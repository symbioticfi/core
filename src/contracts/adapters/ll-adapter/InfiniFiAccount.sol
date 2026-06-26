// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";

import {IInfiniFiAccount} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiAccount.sol";
import {IInfiniFiGateway} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiGateway.sol";
import {IInfiniFiUnwindingModule} from "../../../interfaces/adapters/ll-adapter/infinifi/IInfiniFiUnwindingModule.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title InfiniFiAccount
/// @notice Account for infiniFi locked iUSD (liUSD) unwinding redemptions.
/// @dev Unwind liUSD to iUSD, then redeem iUSD only when the gateway can pay it instantly.
contract InfiniFiAccount is CooldownAccount, IInfiniFiAccount {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IInfiniFiAccount
    address public immutable GATEWAY;
    /// @inheritdoc IInfiniFiAccount
    address public immutable UNWINDING_MODULE;
    /// @inheritdoc IInfiniFiAccount
    address public immutable IUSD;
    /// @inheritdoc IInfiniFiAccount
    uint32 public immutable UNWINDING_EPOCHS;

    /* STATE VARIABLES */

    /// @inheritdoc IInfiniFiAccount
    uint48[] public unwindingTimestamps;

    /* CONSTRUCTOR */

    /// @notice Creates the infiniFi account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address gateway,
        address unwindingModule,
        address iusd,
        uint32 unwindingEpochs,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        GATEWAY = gateway;
        UNWINDING_MODULE = unwindingModule;
        IUSD = iusd;
        UNWINDING_EPOCHS = unwindingEpochs;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending unwinding and held iUSD value in vault assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 receiptAmount = IERC20(IUSD).balanceOf(address(this));
        for (uint256 i; i < unwindingTimestamps.length; ++i) {
            receiptAmount += IInfiniFiUnwindingModule(UNWINDING_MODULE).balanceOf(address(this), unwindingTimestamps[i]);
        }
        if (receiptAmount > 0) {
            assets = _redemptionTokenToAssets(IUSD, receiptAmount);
        }
    }

    /// @dev Completes matured unwindings and redeems held iUSD only when fully payable instantly.
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
            try IInfiniFiGateway(GATEWAY)
                .redeem(address(this), receiptAmount, _redemptionTokenToAssets(IUSD, receiptAmount)) {}
                catch {}
        }
    }

    /// @dev Starts unwinding the held liUSD balance. Unwinding positions are keyed by
    ///      keccak(account, block.timestamp), so a second request in the same second would collide
    ///      and revert: lastRequestTimestamp equals block.timestamp only when a request already
    ///      happened this second, so it is skipped and the balance is picked up by a later sync.
    function _requestRedeem() internal override returns (bool) {
        if (lastRequestTimestamp == block.timestamp) {
            return false;
        }

        IInfiniFiGateway(GATEWAY).startUnwinding(IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)), UNWINDING_EPOCHS);
        unwindingTimestamps.push(uint48(block.timestamp));
        return true;
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter and vault.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        IERC20(TOKEN_TO_REDEEM).forceApprove(GATEWAY, type(uint256).max);
        IERC20(IUSD).forceApprove(GATEWAY, type(uint256).max);
    }
}
