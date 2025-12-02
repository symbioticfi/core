// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {IVaultStorage} from "../../interfaces/vault/IVaultStorage.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

abstract contract VaultStorage is StaticDelegateCallable, IVaultStorage {
    using Checkpoints for Checkpoints.Trace256;
    using SafeCast for uint256;

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
     * @notice Total claimable withdrawal assets in the global withdrawal pool.
     * @dev These withdrawals have finished their delay and are no longer slashable.
     */
    uint256 public claimableWithdrawals;

    /**
     * @notice Total claimable withdrawal shares in the global withdrawal pool.
     * @dev These withdrawals have finished their delay and are no longer slashable.
     */
    uint256 public claimableWithdrawalShares;

    /**
     * @notice Aggregated withdrawal window.
     * @dev Tracks the total shares that unlock at a given timestamp.
     */
    struct WithdrawalWindow {
        uint48 unlockAt;
        uint256 shares;
    }

    /**
     * @notice Queue of withdrawal windows ordered by unlockAt.
     * @dev Used to move withdrawals from pending to claimable once the unlock time passes.
     */
    WithdrawalWindow[] internal _withdrawalQueue;

    /**
     * @notice Cursor pointing to the first pending withdrawal window in the queue.
     */
    uint256 internal _withdrawalQueueCursor;

    /**
     * @notice Withdrawal entries for each account.
     * @dev Each entry is packed as (shares << 48) | unlockAt
     */
    mapping(address account => uint256[]) public withdrawalEntries;

    /**
     * @notice Get total withdrawal shares for a particular account (for slashing).
     * @param account account to get the total withdrawal shares for
     * @return total number of withdrawal shares for the account
     */
    function withdrawalSharesOf(address account) public view returns (uint256) {
        uint256[] storage entries = withdrawalEntries[account];
        uint256 total;
        uint256 length = entries.length;
        uint48 now_ = Time.timestamp();
        for (uint256 i; i < length; ++i) {
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(entries[i]);
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

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeStake;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    constructor(address delegatorFactory, address slasherFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    /**
     * @notice Get the current timestamp.
     * @return current timestamp
     */
    function currentTime() public view returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @notice Get all slashable unlock windows (windows where unlockAt > now).
     * @param now_ current timestamp
     * @return windows array of unlock windows that are still slashable
     * @dev This is a helper for iterating over slashable withdrawals.
     *      In practice, we'll track the max unlock window and iterate backwards.
     */
    function getSlashableWindows(uint48 now_) public view returns (uint48[] memory windows) {
        // This is a simplified version - in practice, you'd want to track active windows
        // For now, we'll calculate on-the-fly in the calling functions
        return windows;
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
