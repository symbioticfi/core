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
    bytes32 public constant FLASH_LOAN_ENABLED_SET_ROLE = keccak256("FLASH_LOAN_ENABLED_SET_ROLE");

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

    uint48 internal _epochDurationInit;

    uint48 internal _epochDuration;

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

    uint256 internal _epochDurationSetEpochsDelay;

    uint256 internal _nextEpochDurationSetEpochsDelay;

    uint256 internal _epochDurationInitIndex;

    uint256 internal _prevEpochDurationInitIndex;

    uint48 internal _prevEpochDurationInit;

    uint48 internal _prevEpochDuration;

    uint48 internal _nextEpochDurationInit;

    uint48 internal _nextEpochDuration;

    uint256 internal _nextEpochInitIndex;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public flashFeeRate;

    /**
     * @inheritdoc IVaultStorage
     */
    address public flashFeeReceiver;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public flashLoanEnabled;

    uint256[42] private __gap;
}
