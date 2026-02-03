// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints as CheckpointsLegacy} from "../libraries/Checkpoints.sol";
import {Checkpoints as Checkpoints} from "../libraries/CheckpointsV2.sol";

import {IVaultV2Storage} from "../../interfaces/vault/IVaultV2Storage.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract VaultV2Storage is StaticDelegateCallable, IVaultV2Storage {
    using CheckpointsLegacy for CheckpointsLegacy.Trace256;
    using CheckpointsLegacy for CheckpointsLegacy.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    address internal immutable DELEGATOR_FACTORY;
    address internal immutable SLASHER_FACTORY;
    address internal immutable REWARDS;
    address internal immutable FEE_REGISTRY;

    address internal immutable MIGRATOR_V1V2;

    /**
     * @inheritdoc IVaultV2Storage
     */
    bool public depositWhitelist;

    /**
     * @inheritdoc IVaultV2Storage
     */
    bool public isDepositLimit;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public collateral;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public burner;

    /**
     * @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
     */
    uint48 internal _epochDurationInit;

    /**
     * @inheritdoc IVaultV2Storage
     */
    uint48 public epochDuration;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public delegator;

    bool internal _isDelegatorInitialized;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public slasher;

    bool internal _isSlasherInitialized;

    /**
     * @inheritdoc IVaultV2Storage
     */
    uint256 public depositLimit;

    /**
     * @inheritdoc IVaultV2Storage
     */
    mapping(address account => bool value) public isDepositorWhitelisted;

    /**
     * @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
     */
    mapping(uint256 epoch => uint256 amount) internal _epochWithdrawals;

    /**
     * @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
     */
    mapping(uint256 epoch => uint256 amount) internal _epochWithdrawalShares;

    /**
     * @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
     */
    mapping(uint256 epoch => mapping(address account => uint256 amount)) internal _epochWithdrawalSharesOf;

    /**
     * @dev DEPRECATED: This variable is kept for storage layout compatibility with previous versions.
     */
    mapping(uint256 epoch => mapping(address account => bool value)) internal _isEpochWithdrawalsClaimed;

    CheckpointsLegacy.Trace256 internal _activeShares;

    CheckpointsLegacy.Trace256 internal _activeStake;

    mapping(address account => CheckpointsLegacy.Trace256 shares) internal _activeSharesOf;

    mapping(address account => Withdrawal[] withdrawals) internal _withdrawalsOf;

    mapping(uint256 bucketIndex => Checkpoints.Trace256 shares) internal _withdrawalShares;

    mapping(uint256 bucketIndex => Checkpoints.Trace256 withdrawals) internal _withdrawals;

    /**
     * @inheritdoc IVaultV2Storage
     */
    mapping(address plugin => uint48 value) public pluginActiveSince;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address[] public plugins;

    /**
     * @inheritdoc IVaultV2Storage
     */
    uint256 public pluginsOwe;

    /**
     * @inheritdoc IVaultV2Storage
     */
    mapping(address plugin => uint256 amount) public pluginOwe;

    /**
     * @inheritdoc IVaultV2Storage
     */
    uint48 public pluginActiveDelay;

    Checkpoints.Trace256 internal _withdrawalSharesCumulative;

    Checkpoints.Trace208 internal _unlockToBucket;

    int256 internal _unclaimedRaw;

    constructor(address delegatorFactory, address slasherFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function activeSharesAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function activeStakeAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeStake.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function activeStake() public view returns (uint256) {
        return _activeStake.latest();
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    // TODO: remove this func?
    function withdrawalShares(uint256 index) public view returns (uint256) {
        return _withdrawalShares[index].latest();
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    // TODO: remove this func?
    function withdrawals(uint256 index) public view returns (uint256) {
        return _withdrawals[index].latest();
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function withdrawalSharesOf(uint256 index, address account) public view returns (uint256) {
        return _withdrawalsOf[account][index].shares;
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function isWithdrawalsClaimed(uint256 index, address account) public view returns (bool) {
        return _withdrawalsOf[account][index].claimed;
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function withdrawalUnlockAfter(uint256 index, address account) public view returns (uint48) {
        return _withdrawalsOf[account][index].unlockAfter;
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function withdrawalsLength(address account) public view returns (uint256) {
        return _withdrawalsOf[account].length;
    }

    function pluginsLength() public view returns (uint256) {
        return plugins.length;
    }

    uint256[39] internal __gap;
}
