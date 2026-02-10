// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IVaultV2Storage} from "./IVaultV2Storage.sol";

// keccak256("DEPOSIT_WHITELIST_SET_ROLE")
bytes32 constant DEPOSIT_WHITELIST_SET_ROLE = 0xbae4ee3de6c709ff9a002e774c5b78cb381560b219213c88ae0f1e207c03c023;
// keccak256("DEPOSITOR_WHITELIST_ROLE")
bytes32 constant DEPOSITOR_WHITELIST_ROLE = 0x9c56d972d63cbb4195b3c1484691dfc220fa96a4c47e7b6613bd82a022029e06;
// keccak256("IS_DEPOSIT_LIMIT_SET_ROLE")
bytes32 constant IS_DEPOSIT_LIMIT_SET_ROLE = 0xc6aaadd7371d5e8f9ed6849dd66a66573a3ba37167d03f4352c9ba5693678fac;
// keccak256("DEPOSIT_LIMIT_SET_ROLE")
bytes32 constant DEPOSIT_LIMIT_SET_ROLE = 0x4a634bc14d77baf979756509ef4298c6f6318af357828612545267ee2eb79233;
// keccak256("SET_PLUGIN_LIMIT_ROLE")
bytes32 constant SET_PLUGIN_LIMIT_ROLE = 0xe0bdc9c1c8c2e75dc2012527eb0fa05a8dda38297bc81683ecb9055988877100;
// keccak256("SWAP_PLUGINS_ROLE")
bytes32 constant SWAP_PLUGINS_ROLE = 0x1c31202be72d3888bec354d209184db36bf8c648652bec1ae036b3ade9fee62e;
// keccak256("ALLOCATE_PLUGIN_ROLE")
bytes32 constant ALLOCATE_PLUGIN_ROLE = 0x519cc70d51fcfd11b60dc29f6c85e08207d46a64951561c68760c7dbedf611dc;
// keccak256("DEALLOCATE_PLUGIN_ROLE")
bytes32 constant DEALLOCATE_PLUGIN_ROLE = 0x2228e59f6ee6ff4b08702cdeaa6118d05e883f4b7df19c7053169d4e74afd4be;

uint256 constant MAX_PLUGINS = 10;

uint48 constant MAX_DURATION = 1000 * 365 days;

/**
 * @title IVault
 * @dev Deprecated functions:
 *      slashableBalanceOf()
 * @dev Removed functions (due to internal-only usage):
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
    error InvalidAddress();
    error InvalidCaptureEpoch();
    error InvalidClaimer();
    error InvalidCollateral();
    error InvalidDelegator();
    error TooLongDuration();
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
    error FeeOnTransferNotSupported();
    error DuplicatePlugin();
    error PluginAllocated();
    error TooManyPlugins();
    error MigrationNotCompleted();
    error DuplicateDepositor();

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
     * @param setPluginLimitRoleHolder address of the initial SET_PLUGIN_LIMIT_ROLE holder
     * @param allocatePluginRoleHolder address of the initial ALLOCATE_PLUGIN_ROLE holder
     * @param pluginsData initial plugin list
     */
    struct InitParams {
        string name;
        string symbol;
        address collateral;
        address burner;
        uint48 epochDuration;
        bool depositWhitelist;
        address[] depositorsWhitelisted;
        bool isDepositLimit;
        uint256 depositLimit;
        address defaultAdminRoleHolder;
        address depositWhitelistSetRoleHolder;
        address depositorWhitelistRoleHolder;
        address isDepositLimitSetRoleHolder;
        address depositLimitSetRoleHolder;
        address setPluginLimitRoleHolder;
        address allocatePluginRoleHolder;
        PluginData[] pluginsData;
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

    struct PluginData {
        address plugin;
        uint208 limit;
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

    event Donate(uint256 amount);

    /**
     * @notice Emitted when a slash happens.
     * @param amount amount of the collateral to slash
     * @param slashedAmount real amount of the collateral slashed
     */
    event OnSlash(uint256 amount, uint256 slashedAmount);

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

    event Deallocate(address indexed plugin, uint256 amount);

    event Allocate(address indexed plugin, uint256 amount);

    /**
     * @notice Emitted when a limit is set.
     * @param plugin address of the plugin
     * @param limit limit of the plugin
     */
    event SetPluginLimit(address indexed plugin, uint208 limit);

    /**
     * @notice Emitted when a plugin is swapped.
     * @param plugin1 address of the first plugin
     * @param plugin2 address of the second plugin
     */
    event SwapPlugins(address indexed plugin1, address indexed plugin2);

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
     * @notice Emitted when a instant withdrawal is made.
     * @param recipient account that received the collateral
     * @param amount amount of the collateral withdrawn
     */
    event InstantWithdraw(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a slashing is synced.
     * @param amount amount of the collateral to slash
     */
    event SyncOwedSlash(uint256 amount);

    /**
     * @notice Emitted when a vault is initialized.
     * @param params initial parameters for the vault
     */
    event Initialize(InitParams params);

    /**
     * @notice Emitted when a vault is migrated.
     * @param params initial parameters for the vault
     * @param newDelegator address of the new delegator
     * @param newSlasher address of the new slasher
     */
    event Migrate(MigrateParams params, address newDelegator, address newSlasher);

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
     * @notice Get a total amount of the active withdrawals for a given duration at a given timestamp.
     * @param duration duration to get the active withdrawals for
     * @param timestamp time point to get the active withdrawals at
     * @return total amount of the active withdrawals
     */
    function activeWithdrawalsForAt(uint48 duration, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of the active withdrawals for a given duration.
     * @param duration duration to get the active withdrawals for
     * @return total amount of the active withdrawals
     */
    function activeWithdrawalsFor(uint48 duration) external view returns (uint256);

    /**
     * @notice Get a total amount of the active withdrawals at a given timestamp.
     * @param timestamp time point to get the active withdrawals at
     * @return total amount of the active withdrawals
     */
    function activeWithdrawalsAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of the withdrawals.
     * @return total amount of the withdrawals
     */
    function activeWithdrawals() external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account at a given timestamp using hints.
     * @param account account to get the active balance for
     * @param timestamp time point to get the active balance for the account at
     * @param hints hints for checkpoints' indexes
     * @return active balance for the account at the timestamp
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes memory hints) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account account to get the active balance for
     * @return active balance for the account
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get how many withdrawals a particular account requested.
     * @param account account to check the withdrawals for
     * @return the number of withdrawals requested by the account
     */
    function withdrawalsOfLength(address account) external view returns (uint256);

    /**
     * @notice Get a number of withdrawal shares for a particular account at a given index (zero if claimed).
     * @param index index to get the number of withdrawal shares for the account at
     * @param account account to get the number of withdrawal shares for
     * @return number of withdrawal shares for the account at the index
     */
    function withdrawalSharesOf(uint256 index, address account) external view returns (uint256);

    /**
     * @notice Get when the withdrawal become claimable for a particular account at a given index.
     * @param index index to check the withdrawals for the account at
     * @param account account to check the withdrawal for
     * @return when the withdrawal is claimable for the account at the index
     */
    function withdrawalUnlockAfter(uint256 index, address account) external view returns (uint48);

    /**
     * @notice Get withdrawals for a particular account at a given index (zero if claimed) using hints.
     * @param index index to get the withdrawals for the account at
     * @param account account to get the withdrawals for
     * @return withdrawals for the account at the index
     */
    function withdrawalsOf(uint256 index, address account) external view returns (uint256);

    function allocatable() external view returns (uint256);

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
     * @notice Instant withdraw collateral from the vault.
     * @param recipient account that received the collateral
     * @param amount amount of the collateral withdrawn
     */
    function instantWithdraw(address recipient, uint256 amount)
        external
        returns (uint256 withdrawnAssets, uint256 burnedShares);

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
     * @notice Set a plugin limit.
     * @param plugin address of the plugin
     * @param limit limit of the plugin
     * @dev Only a SET_PLUGIN_LIMIT_ROLE holder can call this function.
     */
    function setPluginLimit(address plugin, uint208 limit) external;

    function swapPlugins(address plugin1, address plugin2) external;

    /**
     * @notice Allocate collateral to the plugin.
     * @param amount amount of the collateral to allocatePlugin
     * @dev Only a plugin can call this function.
     */
    function allocatePlugin(address plugin, uint256 amount) external returns (uint256 allocated);

    /**
     * @notice Deallocate collateral from the plugin.
     * @param amount amount of the collateral to deallocatePlugin
     * @dev Only a plugin can call this function.
     */
    function deallocatePlugin(address plugin, uint256 amount) external returns (uint256 deallocated);

    function skimPlugins() external;

    function deallocatePlugins() external;
}
