// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {StaticDelegateCallable} from "../../../src/contracts/common/StaticDelegateCallable.sol";

import {Checkpoints} from "../../../src/contracts/libraries/Checkpoints.sol";

import {IVaultStorageV1} from "./IVaultStorageV1.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

abstract contract VaultStorageV1 is StaticDelegateCallable, IVaultStorageV1 {
    using Checkpoints for Checkpoints.Trace256;
    using SafeCast for uint256;

    /**
     * @inheritdoc IVaultStorageV1
     */
    bytes32 public constant DEPOSIT_WHITELIST_SET_ROLE = keccak256("DEPOSIT_WHITELIST_SET_ROLE");

    /**
     * @inheritdoc IVaultStorageV1
     */
    bytes32 public constant DEPOSITOR_WHITELIST_ROLE = keccak256("DEPOSITOR_WHITELIST_ROLE");

    /**
     * @inheritdoc IVaultStorageV1
     */
    bytes32 public constant IS_DEPOSIT_LIMIT_SET_ROLE = keccak256("IS_DEPOSIT_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultStorageV1
     */
    bytes32 public constant DEPOSIT_LIMIT_SET_ROLE = keccak256("DEPOSIT_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultStorageV1
     */
    address public immutable DELEGATOR_FACTORY;

    /**
     * @inheritdoc IVaultStorageV1
     */
    address public immutable SLASHER_FACTORY;

    /**
     * @inheritdoc IVaultStorageV1
     */
    bool public depositWhitelist;

    /**
     * @inheritdoc IVaultStorageV1
     */
    bool public isDepositLimit;

    /**
     * @inheritdoc IVaultStorageV1
     */
    address public collateral;

    /**
     * @inheritdoc IVaultStorageV1
     */
    address public burner;

    /**
     * @inheritdoc IVaultStorageV1
     */
    uint48 public epochDurationInit;

    /**
     * @inheritdoc IVaultStorageV1
     */
    uint48 public epochDuration;

    /**
     * @inheritdoc IVaultStorageV1
     */
    address public delegator;

    /**
     * @inheritdoc IVaultStorageV1
     */
    bool public isDelegatorInitialized;

    /**
     * @inheritdoc IVaultStorageV1
     */
    address public slasher;

    /**
     * @inheritdoc IVaultStorageV1
     */
    bool public isSlasherInitialized;

    /**
     * @inheritdoc IVaultStorageV1
     */
    uint256 public depositLimit;

    /**
     * @inheritdoc IVaultStorageV1
     */
    mapping(address account => bool value) public isDepositorWhitelisted;

    /**
     * @inheritdoc IVaultStorageV1
     */
    mapping(uint256 epoch => uint256 amount) public withdrawals;

    /**
     * @inheritdoc IVaultStorageV1
     */
    mapping(uint256 epoch => uint256 amount) public withdrawalShares;

    /**
     * @inheritdoc IVaultStorageV1
     */
    mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalSharesOf;

    /**
     * @inheritdoc IVaultStorageV1
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
     * @inheritdoc IVaultStorageV1
     */
    function epochAt(uint48 timestamp) public view returns (uint256) {
        if (timestamp < epochDurationInit) {
            revert InvalidTimestamp();
        }
        return (timestamp - epochDurationInit) / epochDuration;
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function currentEpoch() public view returns (uint256) {
        return (Time.timestamp() - epochDurationInit) / epochDuration;
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function currentEpochStart() public view returns (uint48) {
        return (epochDurationInit + currentEpoch() * epochDuration).toUint48();
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function previousEpochStart() public view returns (uint48) {
        uint256 epoch = currentEpoch();
        if (epoch == 0) {
            revert NoPreviousEpoch();
        }
        return (epochDurationInit + (epoch - 1) * epochDuration).toUint48();
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function nextEpochStart() public view returns (uint48) {
        return (epochDurationInit + (currentEpoch() + 1) * epochDuration).toUint48();
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function activeSharesAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function activeStakeAt(uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeStake.upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function activeStake() public view returns (uint256) {
        return _activeStake.latest();
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorageV1
     */
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    uint256[50] private __gap;
}
