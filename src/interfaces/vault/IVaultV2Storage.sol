// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultStorage
 * @dev Deprecated signatures:
 *      epochDurationInit()
 *      epochAt(uint48)
 *      currentEpoch()
 *      currentEpochStart()
 *      previousEpochStart()
 *      nextEpochStart()
 */
interface IVaultV2Storage {
    error InvalidTimestamp();
    error NoPreviousEpoch();

    struct Withdrawal {
        bool claimed;
        uint48 unlockAt;
        uint256 shares;
    }

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
     * @notice Get a deposit limit enabler/disabler's role.
     * @return identifier of the deposit limit enabler/disabler role
     */
    function IS_DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a deposit limit setter's role.
     * @return identifier of the deposit limit setter role
     */
    function DEPOSIT_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a plugin adder's role.
     * @return identifier of the plugin adder role
     */
    function ADD_PLUGIN_ROLE() external view returns (bytes32);

    /**
     * @notice Get a plugin remover's role.
     * @return identifier of the plugin remover role
     */
    function REMOVE_PLUGIN_ROLE() external view returns (bytes32);

    /**
     * @notice Get the delegator factory's address.
     * @return address of the delegator factory
     */
    function DELEGATOR_FACTORY() external view returns (address);

    /**
     * @notice Get the slasher factory's address.
     * @return address of the slasher factory
     */
    function SLASHER_FACTORY() external view returns (address);

    /**
     * @notice Get the rewards address.
     * @return address of the rewards
     */
    function REWARDS() external view returns (address);

    /**
     * @notice Get the fee registry address.
     * @return address of the fee registry
     */
    function FEE_REGISTRY() external view returns (address);

    /**
     * @notice Get a vault collateral.
     * @return address of the underlying collateral
     */
    function collateral() external view returns (address);

    /**
     * @notice Get a burner to issue debt to (e.g., 0xdEaD or some unwrapper contract).
     * @return address of the burner
     */
    function burner() external view returns (address);

    /**
     * @notice Get a delegator (it delegates the vault's stake to networks and operators).
     * @return address of the delegator
     */
    function delegator() external view returns (address);

    /**
     * @notice Get if the delegator is initialized.
     * @return if the delegator is initialized
     */
    function isDelegatorInitialized() external view returns (bool);

    /**
     * @notice Get a slasher (it provides networks a slashing mechanism).
     * @return address of the slasher
     */
    function slasher() external view returns (address);

    /**
     * @notice Get if the slasher is initialized.
     * @return if the slasher is initialized
     */
    function isSlasherInitialized() external view returns (bool);

    /**
     * @notice Get a duration of the vault withdrawal delay.
     * @return duration of the withdrawal delay
     */
    function epochDuration() external view returns (uint48);

    /**
     * @notice Get a duration before a plugin becomes active.
     * @return delay before a plugin becomes active
     */
    function pluginActiveDelay() external view returns (uint48);

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
     * @notice Get if the deposit limit is set.
     * @return if the deposit limit is set
     */
    function isDepositLimit() external view returns (bool);

    /**
     * @notice Get a deposit limit (maximum amount of the active stake that can be in the vault simultaneously).
     * @return deposit limit
     */
    function depositLimit() external view returns (uint256);

    /**
     * @notice Get a total number of active shares in the vault at a given timestamp using a hint.
     * @param timestamp time point to get the total number of active shares at
     * @param hint hint for the checkpoint index
     * @return total number of active shares at the timestamp
     */
    function activeSharesAt(uint48 timestamp, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get a total number of active shares in the vault.
     * @return total number of active shares
     */
    function activeShares() external view returns (uint256);

    /**
     * @notice Get a total amount of active stake in the vault at a given timestamp using a hint.
     * @param timestamp time point to get the total active stake at
     * @param hint hint for the checkpoint index
     * @return total amount of active stake at the timestamp
     */
    function activeStakeAt(uint48 timestamp, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get a total amount of active stake in the vault.
     * @return total amount of active stake
     */
    function activeStake() external view returns (uint256);

    /**
     * @notice Get a total number of active shares for a particular account at a given timestamp using a hint.
     * @param account account to get the number of active shares for
     * @param timestamp time point to get the number of active shares for the account at
     * @param hint hint for the checkpoint index
     * @return number of active shares for the account at the timestamp
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get a number of active shares for a particular account.
     * @param account account to get the number of active shares for
     * @return number of active shares for the account
     */
    function activeSharesOf(address account) external view returns (uint256);

    /**
     * @notice Get a total amount of the withdrawals at a given bucket index.
     * @param index index to get the total amount of the withdrawals at
     * @return total amount of the withdrawals at the bucket index
     */
    function withdrawals(uint256 index) external view returns (uint256);

    /**
     * @notice Get a total number of withdrawal shares at a given bucket index.
     * @param index index to get the total number of withdrawal shares at
     * @return total number of withdrawal shares at the bucket index
     */
    function withdrawalShares(uint256 index) external view returns (uint256);

    /**
     * @notice Get a number of withdrawal shares for a particular account at a given index (zero if claimed).
     * @param index index to get the number of withdrawal shares for the account at
     * @param account account to get the number of withdrawal shares for
     * @return number of withdrawal shares for the account at the index
     */
    function withdrawalSharesOf(uint256 index, address account) external view returns (uint256);

    /**
     * @notice Get if the withdrawal is claimed for a particular account at a given index.
     * @param index index to check the withdrawal for the account at
     * @param account account to check the withdrawal for
     * @return if the withdrawal is claimed for the account at the index
     */
    function isWithdrawalsClaimed(uint256 index, address account) external view returns (bool);

    /**
     * @notice Get when the withdrawal become claimable for a particular account at a given index.
     * @param index index to check the withdrawals for the account at
     * @param account account to check the withdrawal for
     * @return when the withdrawal is claimable for the account at the index
     */
    function withdrawalUnlockAt(uint256 index, address account) external view returns (uint48);

    /**
     * @notice Get how many withdrawals a particular account requested.
     * @param account account to check the withdrawals for
     * @return the number of withdrawals requested by the account
     */
    function withdrawalsLength(address account) external view returns (uint256);

    /**
     * @notice Get when the plugin became active.
     * @param plugin address of the plugin
     * @return when the plugin became active
     */
    function pluginActiveSince(address plugin) external view returns (uint48);

    function plugins(uint256 index) external view returns (address);

    function pluginsLength() external view returns (uint256);

    function pluginsOwe() external view returns (uint256);

    function pluginOwe(address plugin) external view returns (uint256);
}
