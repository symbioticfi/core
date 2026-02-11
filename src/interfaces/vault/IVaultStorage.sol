// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultStorage
 * @notice Interface for the VaultStorage contract.
 */
interface IVaultStorage {
    error InvalidTimestamp();
    error NoPreviousEpoch();

    /**
     * @notice Get a deposit whitelist enabler/disabler's role.
     * @return Identifier Of the whitelist enabler/disabler role.
     */
    function DEPOSIT_WHITELIST_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a depositor whitelist status setter's role.
     * @return Identifier Of the depositor whitelist status setter role.
     */
    function DEPOSITOR_WHITELIST_ROLE() external view returns (bytes32);

    /**
     * @notice Get a deposit limit enabler/disabler's role.
     * @return Identifier Of the deposit limit enabler/disabler role.
     */
    function IS_DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a deposit limit setter's role.
     * @return Identifier Of the deposit limit setter role.
     */
    function DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the delegator factory's address.
     * @return Address Of the delegator factory.
     */
    function DELEGATOR_FACTORY() external view returns (address);

    /**
     * @notice Get the slasher factory's address.
     * @return Address Of the slasher factory.
     */
    function SLASHER_FACTORY() external view returns (address);

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
     * @notice Get a delegator (it delegates the vault's stake to networks and operators).
     * @return Address Of the delegator.
     */
    function delegator() external view returns (address);

    /**
     * @notice Get if the delegator is initialized.
     * @return If The delegator is initialized.
     */
    function isDelegatorInitialized() external view returns (bool);

    /**
     * @notice Get a slasher (it provides networks a slashing mechanism).
     * @return Address Of the slasher.
     */
    function slasher() external view returns (address);

    /**
     * @notice Get if the slasher is initialized.
     * @return If The slasher is initialized.
     */
    function isSlasherInitialized() external view returns (bool);

    /**
     * @notice Get a time point of the epoch duration set.
     * @return Time Point of the epoch duration set.
     */
    function epochDurationInit() external view returns (uint48);

    /**
     * @notice Get a duration of the vault epoch.
     * @return Duration Of the epoch.
     */
    function epochDuration() external view returns (uint48);

    /**
     * @notice Get an epoch at a given timestamp.
     * @param timestamp Time point to get the epoch at.
     * @return Epoch At the timestamp.
     * @dev Reverts if the timestamp is less than the start of the epoch 0.
     */
    function epochAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a current vault epoch.
     * @return Current Epoch.
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Get a start of the current vault epoch.
     * @return Start Of the current epoch.
     */
    function currentEpochStart() external view returns (uint48);

    /**
     * @notice Get a start of the previous vault epoch.
     * @return Start Of the previous epoch.
     * @dev Reverts if the current epoch is 0.
     */
    function previousEpochStart() external view returns (uint48);

    /**
     * @notice Get a start of the next vault epoch.
     * @return Start Of the next epoch.
     */
    function nextEpochStart() external view returns (uint48);

    /**
     * @notice Get if the deposit whitelist is enabled.
     * @return If The deposit whitelist is enabled.
     */
    function depositWhitelist() external view returns (bool);

    /**
     * @notice Get if a given account is whitelisted as a depositor.
     * @param account Address to check.
     * @return If The account is whitelisted as a depositor.
     */
    function isDepositorWhitelisted(address account) external view returns (bool);

    /**
     * @notice Get if the deposit limit is set.
     * @return If The deposit limit is set.
     */
    function isDepositLimit() external view returns (bool);

    /**
     * @notice Get a deposit limit (maximum amount of the active stake that can be in the vault simultaneously).
     * @return Deposit Limit.
     */
    function depositLimit() external view returns (uint256);

    /**
     * @notice Get a total number of active shares in the vault at a given timestamp using a hint.
     * @param timestamp Time point to get the total number of active shares at.
     * @param hint Hint for the checkpoint index.
     * @return Total Number of active shares at the timestamp.
     */
    function activeSharesAt(uint48 timestamp, bytes memory hint) external view returns (uint256);

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
    function activeStakeAt(uint48 timestamp, bytes memory hint) external view returns (uint256);

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
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get a number of active shares for a particular account.
     * @param account Account to get the number of active shares for.
     * @return Number Of active shares for the account.
     */
    function activeSharesOf(address account) external view returns (uint256);

    /**
     * @notice Get a total amount of the withdrawals at a given epoch.
     * @param epoch Epoch to get the total amount of the withdrawals at.
     * @return Total Amount of the withdrawals at the epoch.
     */
    function withdrawals(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get a total number of withdrawal shares at a given epoch.
     * @param epoch Epoch to get the total number of withdrawal shares at.
     * @return Total Number of withdrawal shares at the epoch.
     */
    function withdrawalShares(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get a number of withdrawal shares for a particular account at a given epoch (zero if claimed).
     * @param epoch Epoch to get the number of withdrawal shares for the account at.
     * @param account Account to get the number of withdrawal shares for.
     * @return Number Of withdrawal shares for the account at the epoch.
     */
    function withdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get if the withdrawals are claimed for a particular account at a given epoch.
     * @param epoch Epoch to check the withdrawals for the account at.
     * @param account Account to check the withdrawals for.
     * @return If The withdrawals are claimed for the account at the epoch.
     */
    function isWithdrawalsClaimed(uint256 epoch, address account) external view returns (bool);
}
