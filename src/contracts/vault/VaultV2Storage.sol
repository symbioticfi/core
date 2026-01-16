// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

import {IVaultV2Storage} from "../../interfaces/vault/IVaultV2Storage.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract VaultV2Storage is StaticDelegateCallable, IVaultV2Storage {
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace512;
    using SafeCast for uint256;

    /**
     * @inheritdoc IVaultV2Storage
     */
    bytes32 public constant DEPOSIT_WHITELIST_SET_ROLE = keccak256("DEPOSIT_WHITELIST_SET_ROLE");

    /**
     * @inheritdoc IVaultV2Storage
     */
    bytes32 public constant DEPOSITOR_WHITELIST_ROLE = keccak256("DEPOSITOR_WHITELIST_ROLE");

    /**
     * @inheritdoc IVaultV2Storage
     */
    bytes32 public constant IS_DEPOSIT_LIMIT_SET_ROLE = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultV2Storage
     */
    bytes32 public constant DEPOSIT_LIMIT_SET_ROLE = keccak256("DEPOSIT_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultV2Storage
     */
    bytes32 public constant ADD_PLUGIN_ROLE = keccak256("ADD_PLUGIN_ROLE");

    /**
     * @inheritdoc IVaultV2Storage
     */
    bytes32 public constant REMOVE_PLUGIN_ROLE = keccak256("REMOVE_PLUGIN_ROLE");

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public immutable DELEGATOR_FACTORY;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public immutable SLASHER_FACTORY;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public immutable PLUGIN_REGISTRY;

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

    /**
     * @inheritdoc IVaultV2Storage
     */
    bool public isDelegatorInitialized;

    /**
     * @inheritdoc IVaultV2Storage
     */
    address public slasher;

    /**
     * @inheritdoc IVaultV2Storage
     */
    bool public isSlasherInitialized;

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

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeStake;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    mapping(address account => Withdrawal[] withdrawals) internal _withdrawalsOf;

    /**
     * @inheritdoc IVaultV2Storage
     */
    mapping(uint256 bucketIndex => uint256 value) public withdrawalShares;

    /**
     * @inheritdoc IVaultV2Storage
     */
    mapping(uint256 bucketIndex => uint256 value) public withdrawals;

    Checkpoints.Trace512 internal _withdrawalSharesCumulative;

    Checkpoints.Trace208 internal _timeToBucket;

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

    int256 internal _unclaimedRaw;

    constructor(address delegatorFactory, address slasherFactory, address pluginRegistry) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
        PLUGIN_REGISTRY = pluginRegistry;
    }

    /**
     * @inheritdoc IVaultV2Storage
     */
    function currentEpochStart() public view returns (uint48) {
        return uint48(block.timestamp);
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
    function withdrawalUnlockAt(uint256 index, address account) public view returns (uint48) {
        return _withdrawalsOf[account][index].unlockAt;
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

    uint256[40] private __gap;
}
