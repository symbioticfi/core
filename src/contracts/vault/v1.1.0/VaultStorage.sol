// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../../common/StaticDelegateCallable.sol";

import {IVaultStorage} from "../../../interfaces/vault/v1.1.0/IVaultStorage.sol";

import {Checkpoints} from "../../libraries/Checkpoints.sol";

abstract contract VaultStorage is StaticDelegateCallable, IVaultStorage {
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

    bytes32 public constant EPOCH_DURATION_SET_ROLE = keccak256("EPOCH_DURATION_SET_ROLE");

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

    uint256 public epochDurationSetEpochsDelay;

    uint256 public epochInit;

    uint48 public previousEpochDurationInit;

    uint48 public previousEpochDuration;

    uint48 public nextEpochDurationInit;

    uint48 public nextEpochDuration;

    constructor(address delegatorFactory, address slasherFactory) {
        DELEGATOR_FACTORY = delegatorFactory;
        SLASHER_FACTORY = slasherFactory;
    }

    uint256[47] private __gap;
}
