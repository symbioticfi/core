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

    /* IMMUTABLES */

    /// @dev Address of the delegator factory.
    address internal immutable DELEGATOR_FACTORY;
    /// @dev Address of the slasher factory.
    address internal immutable SLASHER_FACTORY;
    /// @dev Address of the rewards contract.
    address internal immutable REWARDS;
    /// @dev Address of the plugin registry.
    address internal immutable PLUGIN_REGISTRY;

    /* STATE VARIABLES */

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
    /// @dev Flag indicating whether the delegator is initialized.
    bool internal _isDelegatorInitialized;
    /// @inheritdoc IVaultV2Storage
    address public slasher;
    /// @dev Flag indicating whether the slasher is initialized.
    bool internal _isSlasherInitialized;
    /// @inheritdoc IVaultV2Storage
    uint256 public depositLimit;
    /// @inheritdoc IVaultV2Storage
    mapping(address account => bool value) public isDepositorWhitelisted;

    /// @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
    mapping(uint256 epoch => uint256 amount) internal __withdrawals;
    /// @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
    mapping(uint256 epoch => uint256 amount) internal __withdrawalShares;
    /// @dev Withdrawal shares per withdrawal index and account.
    mapping(uint256 index => mapping(address account => uint256 amount)) internal _withdrawalSharesOf;
    /// @inheritdoc IVaultV2Storage
    mapping(uint256 index => mapping(address account => bool value)) public isWithdrawalsClaimed;

    /// @dev Checkpointed total active shares.
    Checkpoints.Trace256 internal _activeShares;
    /// @dev Checkpointed total active stake.
    Checkpoints.Trace256 internal _activeStake;
    /// @dev Checkpointed active shares per account.
    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    /// @dev Timestamp when migration to the current storage model occurred.
    uint48 internal __migrateTimestamp;
    /// @dev Epoch index at migration.
    uint48 internal __migrateEpoch;
    /// @dev Timestamp of the next epoch boundary at migration.
    uint48 internal __migrateNextEpochTimestamp;

    /// @dev Number of withdrawal requests per account.
    mapping(address account => uint256 value) internal _withdrawalsOfLength;
    /// @dev Withdrawal unlock timestamp per withdrawal index and account.
    mapping(uint256 index => mapping(address account => uint48 timestamp)) internal _withdrawalUnlockAfter;
    /// @dev Checkpointed withdrawal shares per bucket.
    mapping(uint256 bucketIndex => CheckpointsV2.Trace256 shares) internal _withdrawalShares;
    /// @dev Checkpointed withdrawal amounts per bucket.
    mapping(uint256 bucketIndex => CheckpointsV2.Trace256 withdrawals) internal _withdrawals;
    /// @dev Checkpointed mapping from unlock time to withdrawal bucket index.
    CheckpointsV2.Trace208 internal _unlockToBucket;
    /// @dev Cumulative withdrawal share checkpoints.
    CheckpointsV2.Trace256 internal _withdrawalSharesCumulative;
    /// @dev Signed accumulator for claimable-vs-unclaimable withdrawal accounting.
    int256 internal _unclaimedRaw;

    /// @inheritdoc IVaultV2Storage
    address[] public plugins;
    /// @inheritdoc IVaultV2Storage
    mapping(address plugin => uint208 amount) public pluginLimit;
    /// @inheritdoc IVaultV2Storage
    uint256 public pluginsAllocated;
    /// @inheritdoc IVaultV2Storage
    mapping(address plugin => uint256 amount) public pluginAllocated;

    /* CONSTRUCTOR */

    constructor(address delegatorFactory, address slasherFactory, address rewards, address pluginRegistry) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
        REWARDS = rewards;
        PLUGIN_REGISTRY = pluginRegistry;
    }

    /* VIEW FUNCTIONS */

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

    /// @inheritdoc IVaultV2Storage
    function pluginsLength() public view returns (uint256) {
        return plugins.length;
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[38] internal __gap;
}
