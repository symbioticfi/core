// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity 0.8.28;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints as CheckpointsV2} from "../libraries/CheckpointsV2.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";

import {IVaultV2Storage} from "../../interfaces/vault/IVaultV2Storage.sol";

/// @title VaultV2Storage
/// @notice Base contract for VaultV2 storage layout and checkpoint getters.
abstract contract VaultV2Storage is StaticDelegateCallable, IVaultV2Storage {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using CheckpointsV2 for CheckpointsV2.Trace256;
    using CheckpointsV2 for CheckpointsV2.Trace208;

    address internal immutable DELEGATOR_FACTORY;
    address internal immutable SLASHER_FACTORY;
    address internal immutable REWARDS;

    address internal immutable MIGRATOR_V1V2;

    /// @inheritdoc IVaultV2Storage
    bool public depositWhitelist;

    /// @inheritdoc IVaultV2Storage
    bool public isDepositLimit;

    /// @inheritdoc IVaultV2Storage
    address public collateral;

    /// @inheritdoc IVaultV2Storage
    address public burner;

    /// @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
    uint48 internal __epochDurationInit;

    /// @inheritdoc IVaultV2Storage
    uint48 public epochDuration;

    /// @inheritdoc IVaultV2Storage
    address public delegator;

    bool internal _isDelegatorInitialized;

    /// @inheritdoc IVaultV2Storage
    address public slasher;

    bool internal _isSlasherInitialized;

    /// @inheritdoc IVaultV2Storage
    uint256 public depositLimit;

    /// @inheritdoc IVaultV2Storage
    mapping(address account => bool value) public isDepositorWhitelisted;

    /// @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
    mapping(uint256 epoch => uint256 amount) internal __withdrawals;

    /// @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
    mapping(uint256 epoch => uint256 amount) internal __withdrawalShares;

    mapping(uint256 index => mapping(address account => uint256 amount)) internal _withdrawalSharesOf;

    /// @inheritdoc IVaultV2Storage
    mapping(uint256 index => mapping(address account => bool value)) public isWithdrawalsClaimed;

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeStake;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    uint48 internal __migrateTimestamp;
    uint48 internal __migrateEpoch;
    uint48 internal __migrateNextEpochTimestamp;

    mapping(address account => uint256 value) internal _withdrawalsOfLength;

    mapping(uint256 index => mapping(address account => uint48 timestamp)) public _withdrawalUnlockAfter;

    mapping(uint256 bucketIndex => CheckpointsV2.Trace256 shares) internal _withdrawalShares;

    mapping(uint256 bucketIndex => CheckpointsV2.Trace256 withdrawals) internal _withdrawals;

    CheckpointsV2.Trace208 internal _unlockToBucket;

    CheckpointsV2.Trace256 internal _withdrawalSharesCumulative;

    int256 internal _unclaimedRaw;

    /// @inheritdoc IVaultV2Storage
    address[] public plugins;

    /// @inheritdoc IVaultV2Storage
    mapping(address plugin => uint208 amount) public pluginLimit;

    /// @inheritdoc IVaultV2Storage
    uint256 public pluginsAllocated;

    /// @inheritdoc IVaultV2Storage
    mapping(address plugin => uint256 amount) public pluginAllocated;

    constructor(address delegatorFactory, address slasherFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    /// @inheritdoc IVaultV2Storage
    function activeSharesAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp, hint);
    }

    /// @inheritdoc IVaultV2Storage
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /// @inheritdoc IVaultV2Storage
    function activeStakeAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeStake.upperLookupRecent(timestamp, hint);
    }

    /// @inheritdoc IVaultV2Storage
    function activeStake() public view returns (uint256) {
        return _activeStake.latest();
    }

    /// @inheritdoc IVaultV2Storage
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /// @inheritdoc IVaultV2Storage
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /// @inheritdoc IVaultV2Storage
    function withdrawalBucket() public view returns (uint208) {
        return _unlockToBucket.latest();
    }

    /// @inheritdoc IVaultV2Storage
    function withdrawalShares(uint256 index) public view returns (uint256) {
        return _withdrawalShares[index].latest();
    }

    /// @inheritdoc IVaultV2Storage
    function withdrawals(uint256 index) public view returns (uint256) {
        return _withdrawals[index].latest();
    }

    function pluginsLength() public view returns (uint256) {
        return plugins.length;
    }

    uint256[38] internal __gap;
}
