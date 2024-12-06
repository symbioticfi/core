// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

import {IVaultStorage} from "../../interfaces/vault/IVaultStorage.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

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
     * @inheritdoc IVaultStorage
     */
    uint48 public epochDurationInit;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public epochDuration;

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
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => uint256 amount) public withdrawals;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => uint256 amount) public withdrawalShares;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalSharesOf;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => mapping(address account => bool value)) public isWithdrawalsClaimed;

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeStake;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    constructor(address delegatorFactory, address slasherFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function epochAt(
        uint48 timestamp
    ) public view returns (uint256) {
        if (timestamp < epochDurationInit) {
            revert InvalidTimestamp();
        }
        return (timestamp - epochDurationInit) / epochDuration;
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function currentEpoch() public view returns (uint256) {
        return (Time.timestamp() - epochDurationInit) / epochDuration;
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function currentEpochStart() public view returns (uint48) {
        return (epochDurationInit + currentEpoch() * epochDuration).toUint48();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function previousEpochStart() public view returns (uint48) {
        uint256 epoch = currentEpoch();
        if (epoch == 0) {
            revert NoPreviousEpoch();
        }
        return (epochDurationInit + (epoch - 1) * epochDuration).toUint48();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function nextEpochStart() public view returns (uint48) {
        return (epochDurationInit + (currentEpoch() + 1) * epochDuration).toUint48();
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
    function activeSharesOf(
        address account
    ) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    uint256[50] private __gap;
}
