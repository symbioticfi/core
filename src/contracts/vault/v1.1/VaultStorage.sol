// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../../common/StaticDelegateCallable.sol";

import {IVaultStorage} from "../../../interfaces/vault/v1.1/IVaultStorage.sol";

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

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant EPOCH_DURATION_SET_ROLE = keccak256("EPOCH_DURATION_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant FLASH_FEE_RATE_SET_ROLE = keccak256("FLASH_FEE_RATE_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant FLASH_FEE_RECEIVER_SET_ROLE = keccak256("FLASH_FEE_RECEIVER_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public constant FLASH_FEE_BASE = 1e9;

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant RETURN_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

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
    uint48 public epochDurationInitInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public epochDurationInternal;

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

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public epochDurationSetEpochsDelay;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public epochInitInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public prevEpochInitInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public prevEpochDurationInitInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public prevEpochDurationInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public nextEpochDurationInitInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public nextEpochDurationInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public nextEpochInitInternal;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public flashFeeRate;

    /**
     * @inheritdoc IVaultStorage
     */
    address public flashFeeReceiver;

    uint256[43] private __gap;
}
