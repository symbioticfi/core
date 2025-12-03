// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVaultStorage {
    error InvalidTimestamp();

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
     * @notice Get a duration of the withdrawal delay (time before withdrawals become claimable).
     * @return duration of the withdrawal delay
     */
    function withdrawalDelay() external view returns (uint48);

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
     * @notice Get total pending withdrawal assets in the global withdrawal pool.
     * @return total amount of pending withdrawal assets
     */
    function withdrawals() external view returns (uint256);

    /**
     * @notice Get total pending withdrawal shares in the global withdrawal pool.
     * @return total number of pending withdrawal shares
     */
    function withdrawalShares() external view returns (uint256);

    /**
     * @notice Get total claimable withdrawal assets in the global withdrawal pool.
     * @return total amount of claimable withdrawal assets
     */
    function claimableWithdrawals() external view returns (uint256);

    /**
     * @notice Get total claimable withdrawal shares in the global withdrawal pool.
     * @return total number of claimable withdrawal shares
     */
    function claimableWithdrawalShares() external view returns (uint256);

    /**
     * @notice Get total withdrawal shares for a particular account (for slashing).
     * @param account account to get the total withdrawal shares for
     * @return total number of withdrawal shares for the account
     */
    function withdrawalSharesOf(address account) external view returns (uint256);

    /**
     * @notice Get all withdrawal entries for a particular account.
     * @param account account to get the withdrawal entries for
     * @return array of packed withdrawal entries (shares << 48 | unlockAt)
     */
    function withdrawalEntries(address account) external view returns (uint256[] memory);
}
