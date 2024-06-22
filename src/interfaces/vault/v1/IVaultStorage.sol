// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IVaultStorage {
    error InvalidTimestamp();
    error NoPreviousEpoch();

    struct Module {
        address address_;
    }

    struct DelayedModule {
        address address_;
        uint48 timestamp;
    }

    /**
     * @notice Get the delegator setter's role.
     */
    function DELEGATOR_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the slasher setter's role.
     */
    function SLASHER_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the deposit whitelist enabler/disabler's role.
     */
    function DEPOSIT_WHITELIST_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the depositor whitelist status setter's role.
     */
    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get a vault collateral.
     * @return vault's underlying collateral
     */
    function collateral() external view returns (address);

    /**
     * @dev Get a burner to issue debt to (e.g. 0xdEaD or some unwrapper contract).
     * @return vault's burner
     */
    function burner() external view returns (address);

    function nextDelegator() external view returns (address, uint48);

    function nextSlasher() external view returns (address, uint48);

    /**
     * @notice Get a time point of the epoch duration set.
     * @return time point of the epoch duration set
     */
    function epochDurationInit() external view returns (uint48);

    /**
     * @notice Get a duration of the vault epoch.
     * @return duration of the epoch
     */
    function epochDuration() external view returns (uint48);

    /**
     * @notice Get an epoch at a given timestamp.
     * @param timestamp time point to get the epoch at
     * @return epoch at the timestamp
     * @dev Reverts if the timestamp is less than the start of the epoch 0.
     */
    function epochAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a current vault epoch.
     * @return current epoch
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Get a start of the current vault epoch.
     * @return start of the current epoch
     */
    function currentEpochStart() external view returns (uint48);

    /**
     * @notice Get a start of the previous vault epoch.
     * @return start of the previous epoch
     * @dev Reverts if the current epoch is 0.
     */
    function previousEpochStart() external view returns (uint48);

    function slasherSetDelay() external view returns (uint48);

    /**
     * @notice Get if the deposit whitelist is enabled.
     * @return if the deposit whitelist is enabled
     */
    function depositWhitelist() external view returns (bool);

    /**
     * @notice Get if a given account is whitelisted as a depositor.
     * @param account address to check
     * @return if the account is whitelisted as a depositor
     */
    function isDepositorWhitelisted(address account) external view returns (bool);

    /**
     * @notice Get a total amount of active shares in the vault at a given timestamp.
     * @param timestamp time point to get the total amount of active shares at
     * @return total amount of active shares at the timestamp
     */
    function activeSharesAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of active shares in the vault.
     * @return total amount of active shares
     */
    function activeShares() external view returns (uint256);

    /**
     * @notice Get a total amount of active supply in the vault at a given timestamp.
     * @param timestamp time point to get the total active supply at
     * @return total amount of active supply at the timestamp
     */
    function activeSupplyAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of active supply in the vault.
     * @return total amount of active supply
     */
    function activeSupply() external view returns (uint256);

    /**
     * @notice Get a total amount of active shares for a particular account at a given timestamp using a hint.
     * @param account account to get the amount of active shares for
     * @param timestamp time point to get the amount of active shares for the account at
     * @param hint hint for the checkpoint index
     * @return amount of active shares for the account at the timestamp
     */
    function activeSharesOfAtHint(address account, uint48 timestamp, uint32 hint) external view returns (uint256);

    /**
     * @notice Get a total amount of active shares for a particular account at a given timestamp.
     * @param account account to get the amount of active shares for
     * @param timestamp time point to get the amount of active shares for the account at
     * @return amount of active shares for the account at the timestamp
     */
    function activeSharesOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an amount of active shares for a particular account.
     * @param account account to get the amount of active shares for
     * @return amount of active shares for the account
     */
    function activeSharesOf(address account) external view returns (uint256);

    /**
     * @notice Get a total number of the activeSharesOf checkpoints for a particular account.
     * @param account account to get the total number of the activeSharesOf checkpoints for
     * @return total number of the activeSharesOf checkpoints for the account
     */
    function activeSharesOfCheckpointsLength(address account) external view returns (uint256);

    /**
     * @notice Get an activeSharesOf checkpoint for a particular account at a given index.
     * @param account account to get the activeSharesOf checkpoint for
     * @param pos index of the checkpoint
     * @return timestamp time point of the checkpoint
     * @return amount of active shares at the checkpoint
     */
    function activeSharesOfCheckpoint(address account, uint32 pos) external view returns (uint48, uint256);

    /**
     * @notice Get a total amount of the withdrawals at a given epoch.
     * @param epoch epoch to get the total amount of the withdrawals at
     * @return total amount of the withdrawals at the epoch
     */
    function withdrawals(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get a total amount of withdrawal shares at a given epoch.
     * @param epoch epoch to get the total amount of withdrawal shares at
     * @return total amount of withdrawal shares at the epoch
     */
    function withdrawalShares(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get an amount of pending withdrawal shares for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the amount of pending withdrawal shares for the account at
     * @param account account to get the amount of pending withdrawal shares for
     * @return amount of pending withdrawal shares for the account at the epoch
     */
    function pendingWithdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);
}
