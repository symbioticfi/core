// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IVaultStorage {
    error InvalidTimestamp();
    error NoPreviousEpoch();

    /**
     * @notice Structure for a module.
     * @param address_ address of the module
     */
    struct Module {
        address address_;
    }

    /**
     * @notice Structure for a module that will be set in the future (if a new address won't be set).
     * @param address_ address of the module
     * @param timestamp timestamp when the module will be set
     */
    struct DelayedModule {
        address address_;
        uint48 timestamp;
    }

    /**
     * @notice Get a slasher setter's role.
     * @return identifier of the slasher setter role
     */
    function SLASHER_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a deposit whitelist enabler/disabler's role.
     * @return identifier of the whitelist enabler/disabler role
     */
    function DEPOSIT_WHITELIST_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a depositor whitelist status setter's role.
     * @return identifier of the depositor whitelist status setter role
     */
    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get the delegator fatory's address.
     * @return address of the delegator fatory
     */
    function DELEGATOR_FACTORY() external view returns (address);

    /**
     * @notice Get the slasher fatory's address.
     * @return address of the slasher fatory
     */
    function SLASHER_FACTORY() external view returns (address);

    /**
     * @notice Get a vault collateral.
     * @return address of the underlying collateral
     */
    function collateral() external view returns (address);

    /**
     * @dev Get a burner to issue debt to (e.g. 0xdEaD or some unwrapper contract).
     * @return address of the burner
     */
    function burner() external view returns (address);

    /**
     * @notice Get a delegator (it delegates the vault's stake to networks and operators).
     * @return address of the delegator
     */
    function delegator() external view returns (address);

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

    /**
     * @notice Get a start of the next vault epoch.
     * @return start of the next epoch
     */
    function nextEpochStart() external view returns (uint48);

    /**
     * @notice Get a delay for a vault in epochs to update a slasher.
     * @return updating a slasher delay in epochs
     */
    function slasherSetEpochsDelay() external view returns (uint256);

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
    function activeSharesOfAt(address account, uint48 timestamp, uint32 hint) external view returns (uint256);

    /**
     * @notice Get a total amount of active shares for a particular account at a given timestamp.
     * @param account account to get the amount of active shares for
     * @param timestamp time point to get the amount of active shares for the account at
     * @return amount of active shares for the account at the timestamp
     */
    function activeSharesOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an activeSharesOf checkpoint for a particular account at a given timestamp.
     * @param account account to get the activeSharesOf checkpoint for
     * @param timestamp time point to get the activeSharesOf checkpoint for the account at
     * @return if the checkpoint exists
     * @return timestamp time point of the checkpoint
     * @return amount of active shares at the checkpoint
     * @return index of the checkpoint
     */
    function activeSharesOfCheckpointAt(
        address account,
        uint48 timestamp
    ) external view returns (bool, uint48, uint256, uint256);

    /**
     * @notice Get an amount of active shares for a particular account.
     * @param account account to get the amount of active shares for
     * @return amount of active shares for the account
     */
    function activeSharesOf(address account) external view returns (uint256);

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
     * @notice Get an amount of withdrawal shares for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the amount of withdrawal shares for the account at
     * @param account account to get the amount of withdrawal shares for
     * @return amount of withdrawal shares for the account at the epoch
     */
    function withdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get if the withdrawals are claimed for a particular account at a given epoch.
     * @param epoch epoch to check the withdrawals for the account at
     * @param account account to check the withdrawals for
     * @return if the withdrawals are claimed for the account at the epoch
     */
    function isWithdrawalsClaimed(uint256 epoch, address account) external view returns (bool);
}
