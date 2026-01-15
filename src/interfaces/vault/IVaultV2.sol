// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IVaultV2Storage} from "./IVaultV2Storage.sol";

/**
 * @title IVault
 * @dev Deprecated signatures:
 *      slashableBalanceOf()
 * @dev Removed signatures (due to internal-only usage):
 *      setDelegator()
 *      setSlasher()
 *      onSlash()
 */
interface IVaultV2 is IMigratableEntity, IVaultV2Storage {
    error AlreadyClaimed();
    error AlreadySet();
    error DelegatorAlreadyInitialized();
    error DepositLimitReached();
    error InsufficientClaim();
    error InsufficientAmount();
    error InsufficientRedemption();
    error InsufficientWithdrawal();
    error InvalidAccount();
    error InvalidCaptureEpoch();
    error InvalidClaimer();
    error InvalidCollateral();
    error InvalidDelegator();
    error InvalidEpochDuration();
    error InvalidLengthEpochs();
    error InvalidOnBehalfOf();
    error InvalidRecipient();
    error InvalidSlasher();
    error MissingRoles();
    error NotDelegator();
    error NotSlasher();
    error NotWhitelistedDepositor();
    error SlasherAlreadyInitialized();
    error TooMuchRedeem();
    error TooMuchWithdraw();
    error WithdrawalNotMatured();
    error PluginNotActive();
    error FeeOnTransferNotSupported();
    error NotPlugin();
    error PluginOwe();

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param name name of the vault
     * @param symbol symbol of the vault
     * @param collateral vault's underlying collateral
     * @param burner vault's burner to issue debt to (e.g., 0xdEaD or some unwrapper contract)
     * @param epochDuration duration of the vault epoch (it determines sync points for withdrawals)
     * @param depositWhitelist if enabling deposit whitelist
     * @param isDepositLimit if enabling deposit limit
     * @param depositLimit deposit limit (maximum amount of the collateral that can be in the vault simultaneously)
     * @param defaultAdminRoleHolder address of the initial DEFAULT_ADMIN_ROLE holder
     * @param depositWhitelistSetRoleHolder address of the initial DEPOSIT_WHITELIST_SET_ROLE holder
     * @param depositorWhitelistRoleHolder address of the initial DEPOSITOR_WHITELIST_ROLE holder
     * @param isDepositLimitSetRoleHolder address of the initial IS_DEPOSIT_LIMIT_SET_ROLE holder
     * @param depositLimitSetRoleHolder address of the initial DEPOSIT_LIMIT_SET_ROLE holder
     */
    struct InitParams {
        string name;
        string symbol;
        address collateral;
        address burner;
        uint48 epochDuration;
        bool depositWhitelist;
        bool isDepositLimit;
        uint256 depositLimit;
        address defaultAdminRoleHolder;
        address depositWhitelistSetRoleHolder;
        address depositorWhitelistRoleHolder;
        address isDepositLimitSetRoleHolder;
        address depositLimitSetRoleHolder;
    }

    /**
     * @notice Initial parameters needed for a vault migration.
     * @param name name of the vault
     * @param symbol symbol of the vault
     * @param delegatorParams parameters for the delegator migration
     * @param slasherParams parameters for the slasher migration
     */
    struct MigrateParams {
        string name;
        string symbol;
        bytes delegatorParams;
        bytes slasherParams;
    }

    /**
     * @notice Hints for an active balance.
     * @param activeSharesOfHint hint for the active shares of checkpoint
     * @param activeStakeHint hint for the active stake checkpoint
     * @param activeSharesHint hint for the active shares checkpoint
     */
    struct ActiveBalanceOfHints {
        bytes activeSharesOfHint;
        bytes activeStakeHint;
        bytes activeSharesHint;
    }

    /**
     * @notice Emitted when a deposit is made.
     * @param depositor account that made the deposit
     * @param onBehalfOf account the deposit was made on behalf of
     * @param amount amount of the collateral deposited
     * @param shares amount of the active shares minted
     */
    event Deposit(address indexed depositor, address indexed onBehalfOf, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is made.
     * @param withdrawer account that made the withdrawal
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral withdrawn
     * @param burnedShares amount of the active shares burned
     * @param mintedShares amount of the epoch withdrawal shares minted
     */
    event Withdraw(
        address indexed withdrawer, address indexed claimer, uint256 amount, uint256 burnedShares, uint256 mintedShares
    );

    /**
     * @notice Emitted when a claim is made.
     * @param claimer account that claimed
     * @param recipient account that received the collateral
     * @param index index the collateral was claimed for
     * @param amount amount of the collateral claimed
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 index, uint256 amount);

    /**
     * @notice Emitted when a batch claim is made.
     * @param claimer account that claimed
     * @param recipient account that received the collateral
     * @param indexes indexes the collateral was claimed for
     * @param amount amount of the collateral claimed
     */
    event ClaimBatch(address indexed claimer, address indexed recipient, uint256[] indexes, uint256 amount);

    /**
     * @notice Emitted when a slash happens.
     * @param amount amount of the collateral to slash
     * @param captureTimestamp time point when the stake was captured
     * @param slashedAmount real amount of the collateral slashed
     */
    event OnSlash(uint256 amount, uint48 captureTimestamp, uint256 slashedAmount);

    /**
     * @notice Emitted when a deposit whitelist status is enabled/disabled.
     * @param status if enabled deposit whitelist
     */
    event SetDepositWhitelist(bool status);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account account for which the whitelist status is set
     * @param status if whitelisted the account
     */
    event SetDepositorWhitelistStatus(address indexed account, bool status);

    /**
     * @notice Emitted when a deposit limit status is enabled/disabled.
     * @param status if enabled deposit limit
     */
    event SetIsDepositLimit(bool status);

    /**
     * @notice Emitted when a deposit limit is set.
     * @param limit deposit limit (maximum amount of the collateral that can be in the vault simultaneously)
     */
    event SetDepositLimit(uint256 limit);

    /**
     * @notice Emitted when a plugin is added.
     * @param plugin address of the plugin
     */
    event AddPlugin(address indexed plugin);

    /**
     * @notice Emitted when a plugin is removed.
     * @param plugin address of the plugin
     */
    event RemovePlugin(address indexed plugin);

    /**
     * @notice Emitted when collateral is pulled from the vault.
     * @param plugin address of the plugin
     * @param amount amount of the collateral pulled
     */
    event Pull(address indexed plugin, uint256 amount);

    /**
     * @notice Emitted when collateral is pushed to the vault.
     * @param plugin address of the plugin
     * @param amount amount of the collateral pushed
     */
    event Push(address indexed plugin, uint256 amount);

    /**
     * @notice Emitted when a delegator is set.
     * @param delegator vault's delegator to delegate the stake to networks and operators
     * @dev Can be set only once.
     */
    event SetDelegator(address indexed delegator);

    /**
     * @notice Emitted when a slasher is set.
     * @param slasher vault's slasher to provide a slashing mechanism to networks
     * @dev Can be set only once.
     */
    event SetSlasher(address indexed slasher);

    /**
     * @notice Check if the vault is fully initialized (a delegator and a slasher are set).
     * @return if the vault is fully initialized
     */
    function isInitialized() external view returns (bool);

    /**
     * @notice Get a total amount of the collateral that can be slashed.
     * @return total amount of the slashable collateral
     */
    function totalStake() external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account at a given timestamp using hints.
     * @param account account to get the active balance for
     * @param timestamp time point to get the active balance for the account at
     * @param hints hints for checkpoints' indexes
     * @return active balance for the account at the timestamp
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes calldata hints) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account account to get the active balance for
     * @return active balance for the account
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get withdrawals for a particular account at a given index (zero if claimed).
     * @param index index to get the withdrawals for the account at
     * @param account account to get the withdrawals for
     * @return withdrawals for the account at the index
     */
    function withdrawalsOf(uint256 index, address account) external view returns (uint256);

    /**
     * @notice Deposit collateral into the vault.
     * @param onBehalfOf account the deposit is made on behalf of
     * @param amount amount of the collateral to deposit
     * @return depositedAmount real amount of the collateral deposited
     * @return mintedShares amount of the active shares minted
     */
    function deposit(address onBehalfOf, uint256 amount)
        external
        returns (uint256 depositedAmount, uint256 mintedShares);

    /**
     * @notice Withdraw collateral from the vault (it will be claimable after the next epoch).
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral to withdraw
     * @return burnedShares amount of the active shares burned
     * @return mintedShares amount of the epoch withdrawal shares minted
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);

    /**
     * @notice Redeem collateral from the vault (it will be claimable after the next epoch).
     * @param claimer account that needs to claim the withdrawal
     * @param shares amount of the active shares to redeem
     * @return withdrawnAssets amount of the collateral withdrawn
     * @return mintedShares amount of the epoch withdrawal shares minted
     */
    function redeem(address claimer, uint256 shares) external returns (uint256 withdrawnAssets, uint256 mintedShares);

    /**
     * @notice Claim collateral from the vault.
     * @param recipient account that receives the collateral
     * @param index index to claim the collateral for
     * @return amount amount of the collateral claimed
     */
    function claim(address recipient, uint256 index) external returns (uint256 amount);

    /**
     * @notice Claim collateral from the vault for multiple indexes.
     * @param recipient account that receives the collateral
     * @param indexes indexes to claim the collateral for
     * @return amount amount of the collateral claimed
     */
    function claimBatch(address recipient, uint256[] calldata indexes) external returns (uint256 amount);

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status if enabling deposit whitelist
     * @dev Only a DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account account for which the whitelist status is set
     * @param status if whitelisting the account
     * @dev Only a DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;

    /**
     * @notice Enable/disable deposit limit.
     * @param status if enabling deposit limit
     * @dev Only a IS_DEPOSIT_LIMIT_SET_ROLE holder can call this function.
     */
    function setIsDepositLimit(bool status) external;

    /**
     * @notice Set a deposit limit.
     * @param limit deposit limit (maximum amount of the collateral that can be in the vault simultaneously)
     * @dev Only a DEPOSIT_LIMIT_SET_ROLE holder can call this function.
     */
    function setDepositLimit(uint256 limit) external;

    /**
     * @notice Add a plugin.
     * @param plugin address of the plugin
     * @dev Only a ADD_PLUGIN_ROLE holder can call this function.
     */
    function addPlugin(address plugin) external;

    /**
     * @notice Remove a plugin.
     * @param plugin address of the plugin
     * @dev Only a REMOVE_PLUGIN_ROLE holder can call this function.
     */
    function removePlugin(address plugin) external;

    /**
     * @notice Pull collateral from the vault.
     * @param amount amount of the collateral to pull
     * @dev Only a plugin can call this function.
     */
    function pull(uint256 amount) external returns (uint256 pulled);

    /**
     * @notice Push collateral to the vault.
     * @param amount amount of the collateral to push
     * @dev Only a plugin can call this function.
     */
    function push(uint256 amount) external;

    /**
     * @dev Migrates a epoch-based withdawal to the fixed-delay-based one.
     * @param epoch An epoch to migrate the withdrawal for.
     * @param account An account to migrate the withdrawal of.
     */
    function migrateWithdrawalsOf(address account, uint48 epoch) external;
}
