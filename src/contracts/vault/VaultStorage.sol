// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {IVaultStorage} from "../../interfaces/vault/IVaultStorage.sol";

import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

abstract contract VaultStorage is StaticDelegateCallable, IVaultStorage {
    using Checkpoints for Checkpoints.Trace256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant DEPOSIT_WHITELIST_SET_ROLE = keccak256("DEPOSIT_WHITELIST_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant DEPOSITOR_WHITELIST_ROLE = keccak256("DEPOSITOR_WHITELIST_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant IS_DEPOSIT_LIMIT_SET_ROLE = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant DEPOSIT_LIMIT_SET_ROLE = keccak256("DEPOSIT_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    address public immutable DELEGATOR_FACTORY;

    /**
     * @inheritdoc IVaultStorage
     */
    address public immutable SLASHER_FACTORY;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public depositWhitelist;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public isDepositLimit;

    /**
     * @inheritdoc IVaultStorage
     */
    address public collateral;

    /**
     * @inheritdoc IVaultStorage
     */
    address public burner;

    /**
     * @notice Initial timestamp for epoch calculation.
     * @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
     *      It is no longer used in the contract logic. Use withdrawalDelay instead.
     */
    uint48 public epochDurationInit;

    /**
     * @notice Duration of the withdrawal delay (time before withdrawals become claimable).
     * @return duration of the withdrawal delay
     */
    uint48 public withdrawalDelay;

    /**
     * @inheritdoc IVaultStorage
     */
    address public delegator;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public isDelegatorInitialized;

    /**
     * @inheritdoc IVaultStorage
     */
    address public slasher;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public isSlasherInitialized;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public depositLimit;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address account => bool value) public isDepositorWhitelisted;

    /**
     * @notice Withdrawal assets per epoch.
     * @dev DEPRECATED: This mapping is kept for storage layout compatibility with previous versions.
     *      It is no longer used in the contract logic. Use the withdrawals() getter function instead.
     */
    mapping(uint256 epoch => uint256 amount) internal _withdrawalsEpoch;

    /**
     * @notice Withdrawal shares per epoch.
     * @dev DEPRECATED: This mapping is kept for storage layout compatibility with previous versions.
     *      It is no longer used in the contract logic. Use the withdrawalShares() getter function instead.
     */
    mapping(uint256 epoch => uint256 amount) internal _withdrawalSharesEpoch;

    /**
     * @notice Withdrawal shares per epoch per account.
     * @dev DEPRECATED: This mapping is kept for storage layout compatibility with previous versions.
     *      It is no longer used in the contract logic. Use _withdrawalEntries mapping instead.
     */
    mapping(uint256 epoch => mapping(address account => uint256 amount)) internal _withdrawalSharesOfEpoch;

    /**
     * @notice Whether withdrawals have been claimed per epoch per account.
     * @dev DEPRECATED: This mapping is kept for storage layout compatibility with previous versions.
     *      It is no longer used in the contract logic. Use _withdrawalEntries mapping instead.
     */
    mapping(uint256 epoch => mapping(address account => bool value)) internal _isWithdrawalsClaimed;

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeStake;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    /**
     * @notice Total pending withdrawal assets in the global withdrawal pool.
     * @dev Only withdrawals that are not yet claimable contribute to this pool.
     */
    uint256 public withdrawals;

    /**
     * @notice Total pending withdrawal shares in the global withdrawal pool.
     * @dev Only withdrawals that are not yet claimable contribute to this pool.
     */
    uint256 public withdrawalShares;

    /**
     * @notice Withdrawal entries for each account stored as a queue.
     * @dev Each entry is packed as (shares << 48) | unlockAt and stored as bytes32.
     *      Uses DoubleEndedQueue for O(1) popFront() operations when claiming.
     */
    mapping(address account => DoubleEndedQueue.Bytes32Deque) internal _withdrawalEntries;

    /**
     * @notice Checkpoint trace mapping unlock timestamp to bucket index.
     * @dev Value is the bucket index used across cumulative withdrawal storage.
     */
    Checkpoints.Trace256 internal _withdrawalBucketTrace;

    /**
     * @notice Index of the first bucket that has not been processed into the claimable pool.
     */
    uint256 internal _processedWithdrawalBucket;

    /**
     * @notice Prefix sum entry containing cumulative shares and assets.
     * @dev Stores cumulative values up to and including a bucket index.
     */
    struct PrefixSum {
        uint256 cumulativeShares;
        uint256 cumulativeAssets;
    }

    /**
     * @notice Cumulative withdrawal shares and assets per bucket, stored as prefix sums.
     * @dev `_withdrawalPrefixSum[i]` equals cumulative shares and assets across buckets `[0, i]`.
     *      Assets are only set when buckets mature; before maturity, cumulativeAssets equals the previous bucket's value.
     */
    PrefixSum[] internal _withdrawalPrefixSum;

    constructor(address delegatorFactory, address slasherFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    /**
     * @notice Get total withdrawal shares for a particular account (for slashing).
     * @param account account to get the total withdrawal shares for
     * @return total number of withdrawal shares for the account
     */
    function withdrawalSharesOf(address account) public view returns (uint256) {
        DoubleEndedQueue.Bytes32Deque storage queue = _withdrawalEntries[account];
        uint256 length = queue.length();
        uint256 total;
        uint48 now_ = Time.timestamp();
        for (uint256 i; i < length; ++i) {
            uint256 packed = uint256(queue.at(i));
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(packed);
            // Only count unclaimed withdrawals (unlockAt > now)
            if (unlockAt > now_) {
                total += shares;
            }
        }
        return total;
    }

    /**
     * @notice Pack shares and unlock timestamp into a single uint256.
     * @param shares withdrawal shares (max 2^208 - 1)
     * @param unlockAt unlock timestamp (uint48)
     * @return packed value: (shares << 48) | unlockAt
     */
    function _packWithdrawal(uint256 shares, uint48 unlockAt) internal pure returns (uint256) {
        // Ensure shares fits in 208 bits
        uint256 maxShares = type(uint256).max >> 48; // 2^208 - 1
        if (shares > maxShares) {
            revert(); // Shares too large
        }
        return (shares << 48) | uint256(unlockAt);
    }

    /**
     * @notice Unpack shares and unlock timestamp from a packed uint256.
     * @param packed packed value
     * @return shares withdrawal shares
     * @return unlockAt unlock timestamp
     */
    function _unpackWithdrawal(uint256 packed) internal pure returns (uint256 shares, uint48 unlockAt) {
        unlockAt = uint48(packed & type(uint48).max);
        shares = packed >> 48;
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeStakeAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeStake.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeStake() public view returns (uint256) {
        return _activeStake.latest();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    uint256[50] private __gap;
}
