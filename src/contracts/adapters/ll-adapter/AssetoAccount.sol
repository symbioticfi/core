// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {CooldownAccount} from "./common/CooldownAccount.sol";
import {CutoffAccount} from "./common/CutoffAccount.sol";

import {IAssetoAccount} from "../../../interfaces/adapters/ll-adapter/asseto/IAssetoAccount.sol";
import {IAssetoManager} from "../../../interfaces/adapters/ll-adapter/asseto/IAssetoManager.sol";
import {ICutoffAccount} from "../../../interfaces/adapters/ll-adapter/ICutoffAccount.sol";
import {IPriceDataOracle} from "../../../interfaces/adapters/ll-adapter/IPriceDataOracle.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AssetoAccount
/// @notice Account for Asseto off-chain settlement redemptions grouped by cutoff buckets.
contract AssetoAccount is CooldownAccount, CutoffAccount, IAssetoAccount {
    using SafeERC20 for IERC20;

    /* STRUCTS */

    /// @dev Cutoff bucket accounting.
    struct Bucket {
        uint256 totalTokenToRedeem;
        uint256 pendingTokenToRedeem;
        uint256 rate;
    }

    /// @dev Pending cutoff entry.
    struct PendingCutoff {
        uint256 amount;
        uint48 bucket;
    }

    /* IMMUTABLES */

    /// @inheritdoc IAssetoAccount
    address public immutable MANAGER;
    /// @inheritdoc IAssetoAccount
    uint48 public immutable VALUATION_DELAY;
    /// @inheritdoc IAssetoAccount
    uint48 public immutable POST_CUTOFF_WINDOW;

    /* STATE VARIABLES */

    /// @inheritdoc IAssetoAccount
    bytes32 public offChainDestination;
    /// @inheritdoc IAssetoAccount
    mapping(uint48 bucket => Bucket data) public buckets;
    /// @inheritdoc IAssetoAccount
    mapping(uint256 key => PendingCutoff data) public pendingCutoffs;

    /// @dev Pending cutoff keys tracked by this account.
    uint256[] internal _pendingKeys;

    /* CONSTRUCTOR */

    /// @notice Creates the Asseto account implementation.
    constructor(
        address oracle,
        address factory,
        uint48 cooldown,
        address tokenToRedeem,
        address manager,
        uint48 valuationDelay,
        uint48 postCutoffWindow,
        address cowSwapSettlement
    ) CooldownAccount(oracle, factory, cooldown, tokenToRedeem, cowSwapSettlement) {
        MANAGER = manager;
        VALUATION_DELAY = valuationDelay;
        POST_CUTOFF_WINDOW = postCutoffWindow;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc CutoffAccount
    function timestampToBucket(uint48 timestamp)
        public
        pure
        override(CutoffAccount, ICutoffAccount)
        returns (uint48 bucket)
    {
        return timestamp;
    }

    /// @inheritdoc CutoffAccount
    function bucketToTimestamp(uint48 bucket)
        public
        pure
        override(CutoffAccount, ICutoffAccount)
        returns (uint48 timestamp)
    {
        return bucket;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns pending cutoff value not already covered by received settlement tokens.
    function _totalAssets() internal view override returns (uint256 assets) {
        uint256 remainingAssets = _settlementAssets();
        if (IAssetoManager(MANAGER).collateral() != _asset) {
            assets = remainingAssets;
        }

        for (uint256 i; i < _pendingKeys.length; ++i) {
            (uint256 value,) = _cutoffValue(_pendingKeys[i]);
            if (remainingAssets >= value) {
                remainingAssets -= value;
            } else {
                assets += value - remainingAssets;
                remainingAssets = 0;
            }
        }
    }

    /// @dev Finalizes pending entries covered by settlement tokens or written off.
    function _finalizeRequests() internal override {
        uint256 remainingAssets = _settlementAssets();

        for (uint256 i = _pendingKeys.length; i > 0; --i) {
            uint256 index = i - 1;
            uint256 key = _pendingKeys[index];
            PendingCutoff storage pendingCutoff = pendingCutoffs[key];
            Bucket storage bucket = buckets[pendingCutoff.bucket];

            if (pendingCutoff.amount > 0 && bucket.rate == 0) {
                uint256 pricingTimestamp = uint256(bucketToTimestamp(pendingCutoff.bucket)) + VALUATION_DELAY;
                if (
                    block.timestamp >= pricingTimestamp
                        && block.timestamp < uint256(bucketToTimestamp(pendingCutoff.bucket)) + POST_CUTOFF_WINDOW
                ) {
                    (uint256 price, uint48 updatedAt) = IPriceDataOracle(ORACLE).getPriceData();
                    if (price > 0 && updatedAt >= pricingTimestamp) {
                        bucket.rate = price;
                        emit FreezeBucket(pendingCutoff.bucket, price);
                    }
                }
            }

            (uint256 value, bool writtenOff) = _cutoffValue(key);
            if (!writtenOff && (bucket.rate == 0 || remainingAssets < value)) {
                continue;
            }
            if (!writtenOff) {
                remainingAssets -= value;
            }

            bucket.pendingTokenToRedeem -= pendingCutoff.amount;
            delete pendingCutoffs[key];
            _pendingKeys[index] = _pendingKeys[_pendingKeys.length - 1];
            _pendingKeys.pop();
        }
    }

    /// @dev Finalizes existing requests and submits a new request when the manager minimum and cooldown permit.
    function _sync() internal override {
        _finalizeRequests();

        if (
            IERC20(TOKEN_TO_REDEEM).balanceOf(address(this)) >= IAssetoManager(MANAGER).minimumRedemptionAmount()
                && (msg.sender == owner()
                    || lastRequestTimestamp == 0
                    || block.timestamp >= lastRequestTimestamp + COOLDOWN)
        ) {
            _requestRedeem();
            lastRequestTimestamp = uint48(block.timestamp);
        }
    }

    /// @dev Burns held Asseto tokens through the manager for off-chain settlement.
    function _requestRedeem() internal override {
        uint256 amount = IERC20(TOKEN_TO_REDEEM).balanceOf(address(this));
        uint256 maximumRedemptionAmount = IAssetoManager(MANAGER).maximumRedemptionAmount();
        if (amount > maximumRedemptionAmount) {
            amount = maximumRedemptionAmount;
        }

        uint256 key = IAssetoManager(MANAGER).redemptionRequestCounter();

        _pendingKeys.push(key);
        uint48 bucket = currentBucket();
        pendingCutoffs[key] = PendingCutoff({amount: amount, bucket: bucket});
        buckets[bucket].totalTokenToRedeem += amount;
        buckets[bucket].pendingTokenToRedeem += amount;
        IAssetoManager(MANAGER).requestRedemptionServicedOffchain(amount, offChainDestination);
    }

    /// @dev Returns a pending cutoff entry's value and whether it is past its counting window.
    function _cutoffValue(uint256 key) internal view returns (uint256 value, bool writtenOff) {
        PendingCutoff memory pendingCutoff = pendingCutoffs[key];
        if (pendingCutoff.amount == 0) {
            return (0, false);
        }

        writtenOff = block.timestamp >= uint256(bucketToTimestamp(pendingCutoff.bucket)) + POST_CUTOFF_WINDOW;
        if (writtenOff) {
            return (0, true);
        }

        uint256 rate = buckets[pendingCutoff.bucket].rate;
        if (rate == 0) {
            (rate,) = IPriceDataOracle(ORACLE).getPriceData();
            if (rate == 0) {
                revert InvalidCutoffPrice();
            }
        }

        value = _tokenToRedeemToAssets(pendingCutoff.amount, rate);
    }

    /// @dev Returns received settlement tokens normalized to vault-asset decimals.
    function _settlementAssets() internal view returns (uint256) {
        address settlementToken = IAssetoManager(MANAGER).collateral();
        uint256 amount = IERC20(settlementToken).balanceOf(address(this));
        return settlementToken == _asset ? amount : _redemptionTokenToAssets(settlementToken, amount);
    }

    /* INITIALIZATION */

    /// @dev Initializes the account for an adapter, vault, and Asseto off-chain destination.
    function _initialize(uint64 initialVersion, address initOwner, bytes memory data) internal override {
        InitParams memory params = abi.decode(data, (InitParams));

        super._initialize(initialVersion, initOwner, abi.encode(params.vault, params.adapter));
        if (IAssetoManager(MANAGER).rwa() != TOKEN_TO_REDEEM) {
            revert InvalidAsset();
        }

        offChainDestination = params.offChainDestination;
        IERC20(TOKEN_TO_REDEEM).forceApprove(MANAGER, type(uint256).max);
    }
}
