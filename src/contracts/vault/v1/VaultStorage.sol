// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultStorage} from "src/interfaces/vault/v1/IVaultStorage.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract VaultStorage is IVaultStorage {
    using Checkpoints for Checkpoints.Trace256;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public constant ADMIN_FEE_BASE = 10_000;

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant ADMIN_FEE_SET_ROLE = keccak256("ADMIN_FEE_SET_ROLE");

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
    address public collateral;
    
    /**
     * @inheritdoc IVaultStorage
     */
    address public burner;

    /**
     * @inheritdoc IVaultStorage
     */
    address public slasher;

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
    uint256 public adminFee;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public depositWhitelist;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address account => bool value) public isDepositorWhitelisted;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address account => uint48 timestamp) public firstDepositAt;

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
    mapping(uint256 epoch => mapping(address account => uint256 amount)) public pendingWithdrawalSharesOf;

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeSupplies;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    /**
     * @inheritdoc IVaultStorage
     */
    function epochAt(uint48 timestamp) public view returns (uint256) {
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
        return uint48(epochDurationInit + currentEpoch() * epochDuration);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function previousEpochStart() public view returns (uint48) {
        uint256 epoch = currentEpoch();
        if (epoch == 0) {
            revert NoPreviousEpoch();
        }
        return uint48(epochDurationInit + (epoch - 1) * epochDuration);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesAt(uint48 timestamp) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp);
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
    function activeSupplyAt(uint48 timestamp) public view returns (uint256) {
        return _activeSupplies.upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSupply() public view returns (uint256) {
        return _activeSupplies.latest();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOfAtHint(address account, uint48 timestamp, uint32 hint) external view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp, hint);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOfCheckpointsLength(address account) external view returns (uint256) {
        return _activeSharesOf[account].length();
    }

    /**
     * @inheritdoc IVaultStorage
     */
    function activeSharesOfCheckpoint(address account, uint32 pos) external view returns (uint48, uint256) {
        Checkpoints.Checkpoint256 memory checkpoint = _activeSharesOf[account].at(pos);
        return (checkpoint._key, checkpoint._value);
    }
}
