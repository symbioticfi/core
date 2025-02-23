// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVaultStorage {
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
     * @notice Get a epoch duration setter's role.
     * @return identifier of the epoch duration setter role
     */
    function EPOCH_DURATION_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a flash fee rate setter's role.
     * @return identifier of the flash fee rate setter role
     */
    function FLASH_FEE_RATE_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a flash fee receiver setter's role.
     * @return identifier of the flash fee receiver setter role
     */
    function FLASH_FEE_RECEIVER_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get a flash fee base.
     * @return flash fee base
     */
    function FLASH_FEE_BASE() external view returns (uint256);

    /**
     * @notice Get a value that must be returned by the flash loan borrower.
     * @return value that must be returned by the flash loan borrower
     */
    function RETURN_VALUE() external view returns (bytes32);

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
     * @notice Get if the deposit whitelist is enabled.
     * @return if the deposit whitelist is enabled
     */
    function depositWhitelist() external view returns (bool);

    /**
     * @notice Get if a given account is whitelisted as a depositor.
     * @param account address to check
     * @return if the account is whitelisted as a depositor
     */
    function isDepositorWhitelisted(
        address account
    ) external view returns (bool);

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
     * @notice Get a total amount of the withdrawals at a given epoch.
     * @param epoch epoch to get the total amount of the withdrawals at
     * @return total amount of the withdrawals at the epoch
     */
    function withdrawals(
        uint256 epoch
    ) external view returns (uint256);

    /**
     * @notice Get a total number of withdrawal shares at a given epoch.
     * @param epoch epoch to get the total number of withdrawal shares at
     * @return total number of withdrawal shares at the epoch
     */
    function withdrawalShares(
        uint256 epoch
    ) external view returns (uint256);

    /**
     * @notice Get a number of withdrawal shares for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the number of withdrawal shares for the account at
     * @param account account to get the number of withdrawal shares for
     * @return number of withdrawal shares for the account at the epoch
     */
    function withdrawalSharesOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get if the withdrawals are claimed for a particular account at a given epoch.
     * @param epoch epoch to check the withdrawals for the account at
     * @param account account to check the withdrawals for
     * @return if the withdrawals are claimed for the account at the epoch
     */
    function isWithdrawalsClaimed(uint256 epoch, address account) external view returns (bool);

    /**
     * @notice Get a delay for the epoch duration set in epochs (internal).
     * @return delay for the epoch duration set
     */
    function epochDurationSetEpochsDelayInternal() external view returns (uint256);

    /**
     * @notice Get the next delay for the epoch duration set in epochs (internal).
     * @return next delay for the epoch duration set
     */
    function nextEpochDurationSetEpochsDelayInternal() external view returns (uint256);

    /**
     * @notice Get the current epoch duration's first epoch (internal).
     * @return the current epoch duration's first epoch
     */
    function epochInitInternal() external view returns (uint256);

    /**
     * @notice Get a time point of the epoch duration set (internal).
     * @return time point of the epoch duration set
     */
    function epochDurationInitInternal() external view returns (uint48);

    /**
     * @notice Get a duration of the epoch (internal).
     * @return duration of the epoch
     */
    function epochDurationInternal() external view returns (uint48);

    /**
     * @notice Get a the previous epoch duration's first epoch (internal).
     * @return the previous epoch duration's first epoch
     */
    function prevEpochInitInternal() external view returns (uint256);

    /**
     * @notice Get a time point of the previous epoch duration set (internal).
     * @return time point of the previous epoch duration set
     */
    function prevEpochDurationInitInternal() external view returns (uint48);

    /**
     * @notice Get a duration of the previous epoch (internal).
     * @return duration of the previous epoch
     */
    function prevEpochDurationInternal() external view returns (uint48);

    /**
     * @notice Get a the next epoch duration's first epoch (internal).
     * @return the next epoch duration's first epoch
     */
    function nextEpochInitInternal() external view returns (uint256);

    /**
     * @notice Get a time point of the next epoch duration set (internal).
     * @return time point of the next epoch duration set
     */
    function nextEpochDurationInitInternal() external view returns (uint48);

    /**
     * @notice Get a duration of the next epoch (internal).
     * @return duration of the next epoch
     */
    function nextEpochDurationInternal() external view returns (uint48);

    /**
     * @notice Get a flash fee rate (100% = 1_000_000_000; 0.03% = 300_000).
     * @return flash fee rate
     */
    function flashFeeRate() external view returns (uint256);

    /**
     * @notice Get a flash fee receiver.
     * @return flash fee receiver
     */
    function flashFeeReceiver() external view returns (address);
}
