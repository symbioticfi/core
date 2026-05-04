// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultV2Storage
 * @notice Interface for the VaultV2Storage contract.
 */
interface IVaultV2Storage {
    /* ERRORS */

    /**
     * @notice Raised when a timestamp argument is invalid for a checkpoint lookup.
     */
    error InvalidTimestamp();

    /**
     * @notice Raised when there is no previous epoch for the requested operation.
     */
    error NoPreviousEpoch();

    /* FUNCTIONS */

    /**
     * @notice Get if the deposit whitelist is enabled.
     * @return If The deposit whitelist is enabled.
     */
    function depositWhitelist() external view returns (bool);

    /**
     * @notice Timestamp when migration to VaultV2 occurred.
     * @return migrateTimestamp Migration timestamp.
     */
    function migrateTimestamp() external view returns (uint48 migrateTimestamp);

    /**
     * @notice Get if the deposit limit is set.
     * @return If The deposit limit is set.
     */
    function isDepositLimit() external view returns (bool);

    /**
     * @notice Get a vault collateral.
     * @return Address Of the underlying collateral.
     */
    function collateral() external view returns (address);

    /**
     * @notice Get a burner to issue debt to (e.g., 0xdEaD or some unwrapper contract).
     * @return Address Of the burner.
     */
    function burner() external view returns (address);

    /**
     * @notice Get a duration of the vault withdrawal delay.
     * @return Duration Of the withdrawal delay.
     */
    function epochDuration() external view returns (uint48);

    /**
     * @notice Get a delegator (it delegates the vault's stake to networks and operators).
     * @return Address Of the delegator.
     */
    function delegator() external view returns (address);

    /**
     * @notice Get a slasher (it provides networks a slashing mechanism).
     * @return Address Of the slasher.
     */
    function slasher() external view returns (address);

    /**
     * @notice Get a deposit limit (maximum amount of the active stake that can be in the vault simultaneously).
     * @return Deposit Limit.
     */
    function depositLimit() external view returns (uint256);

    /**
     * @notice Get if a given account is whitelisted as a depositor.
     * @param account Address to check.
     * @return If The account is whitelisted as a depositor.
     */
    function isDepositorWhitelisted(address account) external view returns (bool);

    /**
     * @notice Get if the withdrawal is claimed for a particular account at a given index.
     * @param index Index to check the withdrawal for the account at.
     * @param account Account to check the withdrawal for.
     * @return If The withdrawal is claimed for the account at the index.
     */
    function isWithdrawalsClaimed(uint256 index, address account) external view returns (bool);

    /**
     * @notice Get a adapter address by index.
     * @param index Index of the adapter in the adapters array.
     * @return Adapter Address at the requested index.
     */
    function adapters(uint256 index) external view returns (address);

    /**
     * @notice Get a one-based adapter position in the adapters array.
     * @dev A zero return value means the adapter is not registered.
     * @param adapter Address of the adapter.
     * @return Index One-based adapter index, or zero if the adapter is not registered.
     */
    function adapterIndex(address adapter) external view returns (uint256);

    /**
     * @notice Get the delay before a newly introduced adapter can receive a non-zero limit.
     * @return Delay Adapter add delay.
     */
    function adaptersAllowDelay() external view returns (uint48);

    /**
     * @notice Get the timestamp when an adapter becomes eligible for a non-zero limit.
     * @param adapter Address of the adapter.
     * @return AvailableAt Timestamp when the adapter can receive a non-zero limit, or zero if not scheduled.
     */
    function adapterAllowedAt(address adapter) external view returns (uint48);

    /**
     * @notice Get a adapter allocation limit.
     * @param adapter Address of the adapter.
     * @return Limit Maximum collateral amount allocatable to the adapter.
     */
    function adapterLimit(address adapter) external view returns (uint208);

    /**
     * @notice Get the total amount allocated across all adapters.
     * @return Allocated Total collateral amount allocated to adapters.
     */
    function adaptersAllocated() external view returns (uint256);

    /**
     * @notice Get the currently allocated amount for a adapter.
     * @param adapter Address of the adapter.
     * @return Allocated Collateral amount allocated to the adapter.
     */
    function adapterAllocated(address adapter) external view returns (uint256);

    /**
     * @notice Get a total number of active shares in the vault at a given timestamp using a hint.
     * @param timestamp Time point to get the total number of active shares at.
     * @param hint Hint for the checkpoint index.
     * @return Total Number of active shares at the timestamp.
     */
    function activeSharesAt(uint48 timestamp, bytes calldata hint) external view returns (uint256);

    /**
     * @notice Get a total number of active shares in the vault.
     * @return Total Number of active shares.
     */
    function activeShares() external view returns (uint256);

    /**
     * @notice Get a total amount of active stake in the vault at a given timestamp using a hint.
     * @param timestamp Time point to get the total active stake at.
     * @param hint Hint for the checkpoint index.
     * @return Total Amount of active stake at the timestamp.
     */
    function activeStakeAt(uint48 timestamp, bytes calldata hint) external view returns (uint256);

    /**
     * @notice Get a total amount of active stake in the vault.
     * @return Total Amount of active stake.
     */
    function activeStake() external view returns (uint256);

    /**
     * @notice Get a total number of active shares for a particular account at a given timestamp using a hint.
     * @param account Account to get the number of active shares for.
     * @param timestamp Time point to get the number of active shares for the account at.
     * @param hint Hint for the checkpoint index.
     * @return Number Of active shares for the account at the timestamp.
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes calldata hint) external view returns (uint256);

    /**
     * @notice Get a number of active shares for a particular account.
     * @param account Account to get the number of active shares for.
     * @return Number Of active shares for the account.
     */
    function activeSharesOf(address account) external view returns (uint256);

    /**
     * @notice Get the index of the last withdrawal bucket.
     * @return Index Of the last withdrawal bucket.
     */
    function withdrawalBucket() external view returns (uint208);

    /**
     * @notice Get a total number of withdrawal shares at a given bucket index.
     * @param index Index to get the total number of withdrawal shares at.
     * @return Total Number of withdrawal shares at the bucket index.
     * @dev Warning: doesn't provide legacy epoch data before.
     */
    function withdrawalShares(uint256 index) external view returns (uint256);

    /**
     * @notice Get a total amount of the withdrawals at a given bucket index.
     * @param index Index to get the total amount of the withdrawals at.
     * @return Total Amount of the withdrawals at the bucket index.
     * @dev Warning: doesn't provide legacy epoch data before.
     */
    function withdrawals(uint256 index) external view returns (uint256);

    /**
     * @notice Get the number of configured adapters.
     * @return Length Number of adapters.
     */
    function adaptersLength() external view returns (uint256);
}
