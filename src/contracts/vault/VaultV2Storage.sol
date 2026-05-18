// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints as CheckpointsV2} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";

import {IVaultV2Storage} from "../../interfaces/vault/IVaultV2Storage.sol";

/// @title VaultV2Storage
/// @notice Base contract for VaultV2 storage layout and checkpoint getters.
abstract contract VaultV2Storage is StaticDelegateCallable, IVaultV2Storage {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using CheckpointsV2 for CheckpointsV2.Trace256;

    /* IMMUTABLES */

    /// @dev Address of the delegator factory.
    address internal immutable DELEGATOR_FACTORY;
    /// @dev Address of the slasher factory.
    address internal immutable SLASHER_FACTORY;
    /// @dev Address of the fee registry.
    address internal immutable FEE_REGISTRY;
    /// @dev Address of the rewards contract.
    address internal immutable REWARDS;
    /// @dev Address of the adapter registry.
    address internal immutable ADAPTER_REGISTRY;

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
    /// @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
    mapping(uint256 index => mapping(address account => bool value)) public __isWithdrawalsClaimed;

    /// @dev Checkpointed total active shares.
    Checkpoints.Trace256 internal _activeShares;
    /// @dev Checkpointed total active stake.
    Checkpoints.Trace256 internal _activeStake;
    /// @dev Checkpointed active shares per account.
    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    /// @inheritdoc IVaultV2Storage
    uint48 public migrateTimestamp;
    /// @dev Epoch index at migration.
    uint48 internal __migrateEpoch;
    /// @dev Timestamp of the next epoch boundary at migration.
    uint48 internal __migrateNextEpochTimestamp;

    /// @dev Withdrawal unlock timestamp per withdrawal index and account.
    CheckpointsV2.Trace256 internal _claimableCumulShares;
    /// @dev Number of withdrawal requests per account.
    mapping(address account => uint256 value) internal _withdrawalsOfLength;
    /// @dev Withdrawal unlock timestamp per withdrawal index and account.
    mapping(uint256 index => mapping(address account => uint256 shares)) internal _withdrawalCumulShares;
    mapping(uint256 index => mapping(address account => uint256 shares)) internal _withdrawalClaimedShares;
    /// @dev Checkpointed withdrawal shares per bucket.
    mapping(uint256 bucketIndex => CheckpointsV2.Trace256 shares) internal _withdrawalShares;
    /// @dev Checkpointed withdrawal amounts per bucket.
    mapping(uint256 bucketIndex => CheckpointsV2.Trace256 amount) internal _withdrawals;
    /// @dev Checkpointed mapping from cumulative withdrawal shares to withdrawal bucket index.
    CheckpointsV2.Trace256 internal _cumulSharesToBucket;
    /// @dev Cumulative withdrawal share checkpoints.
    CheckpointsV2.Trace256 internal _withdrawalSharesCumulative;
    /// @dev Cumulative withdrawal share checkpoints per account.
    mapping(address account => CheckpointsV2.Trace256 shares) internal _withdrawalSharesCumulativeOf;
    /// @dev Signed accumulator for claimable-vs-unclaimable withdrawal accounting.
    int256 internal _unclaimedRaw;

    /// @inheritdoc IVaultV2Storage
    address[] public adapters;
    /// @inheritdoc IVaultV2Storage
    mapping(address adapter => uint256 position) public adapterIndex;
    /// @inheritdoc IVaultV2Storage
    uint48 public adaptersAllowDelay;
    /// @inheritdoc IVaultV2Storage
    mapping(address adapter => uint48 timestamp) public adapterAllowedAt;
    /// @inheritdoc IVaultV2Storage
    mapping(address adapter => uint208 amount) public adapterLimit;
    /// @inheritdoc IVaultV2Storage
    uint256 public adaptersAllocated;
    /// @inheritdoc IVaultV2Storage
    mapping(address adapter => uint256 amount) public adapterAllocated;

    /* CONSTRUCTOR */

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address feeRegistry,
        address rewards,
        address adapterRegistry
    ) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
        FEE_REGISTRY = feeRegistry;
        REWARDS = rewards;
        ADAPTER_REGISTRY = adapterRegistry;
    }

    /* VIEW FUNCTIONS */

    /// @inheritdoc IVaultV2Storage
    function activeSharesAt(uint48 timestamp, bytes calldata hint) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp, hint);
    }

    /// @inheritdoc IVaultV2Storage
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /// @inheritdoc IVaultV2Storage
    function activeStakeAt(uint48 timestamp, bytes calldata hint) public view returns (uint256) {
        return _activeStake.upperLookupRecent(timestamp, hint);
    }

    /// @inheritdoc IVaultV2Storage
    function activeStake() public view returns (uint256) {
        return _activeStake.latest();
    }

    /// @inheritdoc IVaultV2Storage
    function activeSharesOfAt(address account, uint48 timestamp, bytes calldata hint) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /// @inheritdoc IVaultV2Storage
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /// @inheritdoc IVaultV2Storage
    function withdrawalBucket() public view returns (uint208) {
        return uint208(_cumulSharesToBucket.latest());
    }

    /// @inheritdoc IVaultV2Storage
    function isWithdrawalsClaimed(uint256 index, address account) public view virtual returns (bool) {
        if (index < __migrateEpoch) {
            // Legacy support.
            return __isWithdrawalsClaimed[index][account];
        }
        return _withdrawalSharesOf[index][account] == _withdrawalClaimedShares[index][account];
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
    function adaptersLength() public view returns (uint256) {
        return adapters.length;
    }

    /* STORAGE GAP */

    /// @dev Reserved storage gap for future upgrades.
    uint256[34] internal __gap;
}
