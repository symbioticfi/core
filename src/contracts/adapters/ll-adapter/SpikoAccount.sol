// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {Account} from "./common/Account.sol";

import {ISpikoAccount} from "../../../interfaces/adapters/ll-adapter/spiko/ISpikoAccount.sol";
import {ISpikoRedemption} from "../../../interfaces/adapters/ll-adapter/spiko/ISpikoRedemption.sol";

import {IERC1363} from "@openzeppelin/contracts/interfaces/IERC1363.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SpikoAccount
/// @notice Account for one in-flight Spiko ERC-1363 redemption settled in a configured stablecoin.
contract SpikoAccount is Account, ISpikoAccount {
    using SafeERC20 for IERC20;

    /* CONSTANTS */

    /// @dev Spiko's published maximum delay before a pending request becomes cancelable.
    uint48 internal constant MAX_ISSUER_DELAY = 14 days;

    /* IMMUTABLES */

    /// @inheritdoc ISpikoAccount
    address public immutable REDEMPTION;
    /// @inheritdoc ISpikoAccount
    address public immutable SETTLEMENT_TOKEN;
    /// @inheritdoc ISpikoAccount
    uint48 public immutable SETTLEMENT_DURATION;

    /* STATE VARIABLES */

    /// @inheritdoc ISpikoAccount
    bytes32 public pendingId;
    /// @inheritdoc ISpikoAccount
    bytes32 public pendingSalt;
    /// @inheritdoc ISpikoAccount
    uint256 public pendingTokenAmount;
    /// @inheritdoc ISpikoAccount
    uint256 public pendingAssets;
    /// @inheritdoc ISpikoAccount
    uint48 public pendingExpiry;
    /// @inheritdoc ISpikoAccount
    uint256 public requestNonce;
    /// @inheritdoc ISpikoAccount
    bool public redemptionPaused;

    /* CONSTRUCTOR */

    /// @notice Creates a Spiko account implementation.
    constructor(
        address oracle,
        address factory,
        address tokenToRedeem,
        address redemption,
        address settlementToken,
        uint48 settlementDuration,
        address cowSwapSettlement
    ) Account(oracle, factory, tokenToRedeem, cowSwapSettlement) {
        REDEMPTION = redemption;
        SETTLEMENT_TOKEN = settlementToken;
        SETTLEMENT_DURATION = settlementDuration;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the status-valid receivable not already covered by newly arrived settlement assets.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 pending = pendingAssets;
        if (pending == 0) {
            return 0;
        }

        (ISpikoRedemption.Status status,) = ISpikoRedemption(REDEMPTION).details(pendingId);
        if (status == ISpikoRedemption.Status.CANCELED) {
            return 0;
        }
        if (status == ISpikoRedemption.Status.NULL) {
            revert InvalidRedemptionStatus();
        }
        if (status == ISpikoRedemption.Status.EXECUTED && block.timestamp >= pendingExpiry) {
            return 0;
        }

        uint256 unreconciled = _unreconciledAssets();
        return pending > unreconciled ? pending - unreconciled : 0;
    }

    /// @dev Reconciles the active request, exposes realized assets, then submits eligible held SPKCC.
    function _sync() internal override {
        bool deferRequest = _syncPendingRequest();

        IERC20 asset = IERC20(_asset);
        asset.forceApprove(adapter, asset.balanceOf(address(this)));

        if (deferRequest || pendingId != bytes32(0)) {
            return;
        }

        bool paused = redemptionPaused;
        if (paused && msg.sender != owner()) {
            return;
        }

        if (_requestRedeem() && paused) {
            redemptionPaused = false;
        }
    }

    /// @dev Reconciles settlement and advances or clears the active request.
    function _syncPendingRequest() internal returns (bool deferRequest) {
        bytes32 id = pendingId;
        if (id == bytes32(0)) {
            return false;
        }

        _reconcileSettlement(id);

        (ISpikoRedemption.Status status, uint48 deadline) = ISpikoRedemption(REDEMPTION).details(id);
        if (status == ISpikoRedemption.Status.PENDING) {
            if (block.timestamp < deadline) {
                return false;
            }

            uint256 amount = pendingTokenAmount;
            uint256 balanceBefore = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
            ISpikoRedemption(REDEMPTION)
                .cancelRedemption(address(this), IERC20(TOKEN_TO_REDEEM), SETTLEMENT_TOKEN, amount, pendingSalt);
            if (IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)) != balanceBefore + amount) {
                revert InvalidRefund();
            }

            emit CancelRedeem(id, amount);
            _clearPendingRequest();
            redemptionPaused = true;
            return true;
        }

        if (status == ISpikoRedemption.Status.CANCELED) {
            emit CancelRedeem(id, pendingTokenAmount);
            _clearPendingRequest();
            redemptionPaused = true;
            return true;
        }

        if (status != ISpikoRedemption.Status.EXECUTED) {
            revert InvalidRedemptionStatus();
        }

        uint256 pending = pendingAssets;
        if (pending == 0) {
            emit CompleteRedeem(id);
            _clearPendingRequest();
        } else if (block.timestamp >= pendingExpiry) {
            emit WriteOff(id, pending);
            _clearPendingRequest();
            redemptionPaused = true;
            return true;
        }
    }

    /// @dev Submits the entire held balance only when Spiko currently authorizes the configured settlement token.
    function _requestRedeem() internal returns (bool requested) {
        IERC20 input = IERC20(TOKEN_TO_REDEEM);
        uint256 amount = input.balanceOf(address(this));
        if (amount == 0 || !_isSettlementOutputEnabled()) {
            return false;
        }
        if (amount < ISpikoRedemption(REDEMPTION).minimum(input)) {
            return false;
        }

        uint256 assets = _tokenToRedeemToAssets(amount);
        uint256 nonce = requestNonce + 1;
        bytes32 salt = bytes32(nonce);
        bytes32 id = keccak256(abi.encodePacked(address(this), input, SETTLEMENT_TOKEN, amount, salt));

        requestNonce = nonce;
        pendingId = id;
        pendingSalt = salt;
        pendingTokenAmount = amount;
        pendingAssets = assets;
        pendingExpiry = 0;

        if (!IERC1363(TOKEN_TO_REDEEM).transferAndCall(REDEMPTION, amount, abi.encode(SETTLEMENT_TOKEN, salt))) {
            revert RedemptionFailed();
        }

        (ISpikoRedemption.Status status, uint48 deadline) = ISpikoRedemption(REDEMPTION).details(id);
        if (
            status != ISpikoRedemption.Status.PENDING || deadline <= block.timestamp
                || deadline > uint48(block.timestamp) + MAX_ISSUER_DELAY
        ) {
            revert InvalidRedemptionRequest();
        }

        uint48 expiry = deadline + SETTLEMENT_DURATION;
        pendingExpiry = expiry;

        emit RequestRedeem(id, amount, assets, salt, deadline, expiry);
        return true;
    }

    /// @dev Returns whether Spiko currently authorizes the configured settlement token for this share class.
    function _isSettlementOutputEnabled() internal view returns (bool) {
        address[] memory outputs = ISpikoRedemption(REDEMPTION).outputsFor(IERC20(TOKEN_TO_REDEEM));
        uint256 length = outputs.length;
        for (uint256 i; i < length; ++i) {
            if (outputs[i] == SETTLEMENT_TOKEN) {
                return true;
            }
        }
        return false;
    }

    /// @dev Reconciles newly arrived settlement against the frozen request value.
    function _reconcileSettlement(bytes32 id) internal {
        uint256 pending = pendingAssets;
        if (pending == 0) {
            return;
        }

        uint256 unreconciled = _unreconciledAssets();
        if (unreconciled == 0) {
            return;
        }

        uint256 reconciled = unreconciled < pending ? unreconciled : pending;
        pending -= reconciled;
        pendingAssets = pending;
        emit ReconcileSettlement(id, reconciled, pending);
    }

    /// @dev Returns assets received since the last sync; exact allowances fall with adapter pulls.
    function _unreconciledAssets() internal view returns (uint256 assets) {
        uint256 balance = IERC20(_asset).balanceOf(address(this));
        uint256 allowance = IERC20(_asset).allowance(address(this), adapter);
        if (balance > allowance) {
            assets = balance - allowance;
        }
    }

    /// @dev Clears the one in-flight request while preserving the monotonic nonce.
    function _clearPendingRequest() internal {
        pendingId = bytes32(0);
        pendingSalt = bytes32(0);
        pendingTokenAmount = 0;
        pendingAssets = 0;
        pendingExpiry = 0;
    }

    /* INITIALIZATION */

    /// @dev Initializes the account and replaces the base maximum approval with an exact balance marker.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        super._initialize(initialVersion, initOwner, data);
        IERC20(_asset).forceApprove(adapter, IERC20(_asset).balanceOf(address(this)));
    }
}
