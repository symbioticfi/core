// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IVaultV2Storage} from "./IVaultV2Storage.sol";

uint64 constant VAULT_V2_VERSION = 3;

// Keccak256("DEPOSIT_WHITELIST_SET_ROLE").
bytes32 constant DEPOSIT_WHITELIST_SET_ROLE = 0xbae4ee3de6c709ff9a002e774c5b78cb381560b219213c88ae0f1e207c03c023;
// Keccak256("DEPOSITOR_WHITELIST_ROLE").
bytes32 constant DEPOSITOR_WHITELIST_ROLE = 0x9c56d972d63cbb4195b3c1484691dfc220fa96a4c47e7b6613bd82a022029e06;
// Keccak256("IS_DEPOSIT_LIMIT_SET_ROLE").
bytes32 constant IS_DEPOSIT_LIMIT_SET_ROLE = 0xc6aaadd7371d5e8f9ed6849dd66a66573a3ba37167d03f4352c9ba5693678fac;
// Keccak256("DEPOSIT_LIMIT_SET_ROLE").
bytes32 constant DEPOSIT_LIMIT_SET_ROLE = 0x4a634bc14d77baf979756509ef4298c6f6318af357828612545267ee2eb79233;
// Keccak256("SET_PLUGIN_LIMIT_ROLE").
bytes32 constant SET_PLUGIN_LIMIT_ROLE = 0xe0bdc9c1c8c2e75dc2012527eb0fa05a8dda38297bc81683ecb9055988877100;
// Keccak256("SWAP_PLUGINS_ROLE").
bytes32 constant SWAP_PLUGINS_ROLE = 0x1c31202be72d3888bec354d209184db36bf8c648652bec1ae036b3ade9fee62e;
// Keccak256("ALLOCATE_PLUGIN_ROLE").
bytes32 constant ALLOCATE_PLUGIN_ROLE = 0x519cc70d51fcfd11b60dc29f6c85e08207d46a64951561c68760c7dbedf611dc;
// Keccak256("DEALLOCATE_PLUGIN_ROLE").
bytes32 constant DEALLOCATE_PLUGIN_ROLE = 0x2228e59f6ee6ff4b08702cdeaa6118d05e883f4b7df19c7053169d4e74afd4be;

uint256 constant MAX_PLUGINS = 10;

uint48 constant MAX_DURATION = 1000 * 365 days;

/**
 * @title IVaultV2
 * @notice Interface for the VaultV2 contract.
 */
interface IVaultV2 is IMigratableEntity, IVaultV2Storage {
    /* ERRORS */

    /**
     * @notice Raised when the caller is not the configured rewards address.
     */
    error NotRewards();

    /**
     * @notice Raised when a withdrawal is already claimed.
     */
    error AlreadyClaimed();

    /**
     * @notice Raised when trying to set a value that is already set.
     */
    error AlreadySet();

    /**
     * @notice Raised when delegator initialization is attempted more than once.
     */
    error DelegatorAlreadyInitialized();

    /**
     * @notice Raised when a deposit would exceed the configured deposit limit.
     */
    error DepositLimitReached();

    /**
     * @notice Raised when there is nothing claimable for the request.
     */
    error InsufficientClaim();

    /**
     * @notice Raised when the provided amount is zero or insufficient.
     */
    error InsufficientAmount();

    /**
     * @notice Raised when redemption output is insufficient.
     */
    error InsufficientRedemption();

    /**
     * @notice Raised when withdrawal output is insufficient.
     */
    error InsufficientWithdrawal();

    /**
     * @notice Raised when an address argument is invalid.
     */
    error InvalidAddress();

    /**
     * @notice Raised when capture epoch input is invalid.
     */
    error InvalidCaptureEpoch();

    /**
     * @notice Raised when claimer address is invalid.
     */
    error InvalidClaimer();

    /**
     * @notice Raised when collateral address is invalid.
     */
    error InvalidCollateral();

    /**
     * @notice Raised when delegator address is invalid.
     */
    error InvalidDelegator();

    /**
     * @notice Raised when epoch duration is outside allowed bounds.
     */
    error TooLongDuration();

    /**
     * @notice Raised when epochs-length input is invalid.
     */
    error InvalidLengthEpochs();

    /**
     * @notice Raised when on-behalf-of address is invalid.
     */
    error InvalidOnBehalfOf();

    /**
     * @notice Raised when recipient address is invalid.
     */
    error InvalidRecipient();

    /**
     * @notice Raised when slasher address is invalid.
     */
    error InvalidSlasher();

    /**
     * @notice Raised when required role holders are missing at initialization.
     */
    error MissingRoles();

    /**
     * @notice Raised when the provided delegator is not recognized.
     */
    error NotDelegator();

    /**
     * @notice Raised when the provided slasher is not recognized.
     */
    error NotSlasher();

    /**
     * @notice Raised when the provided plugin is not whitelisted in plugin registry.
     */
    error NotPlugin();

    /**
     * @notice Raised when depositor is not in the whitelist while whitelist is enabled.
     */
    error NotWhitelistedDepositor();

    /**
     * @notice Raised when slasher initialization is attempted more than once.
     */
    error SlasherAlreadyInitialized();

    /**
     * @notice Raised when redeeming more shares than available.
     */
    error TooMuchRedeem();

    /**
     * @notice Raised when withdrawing more assets than available.
     */
    error TooMuchWithdraw();

    /**
     * @notice Raised when withdrawal is not yet matured.
     */
    error WithdrawalNotMatured();

    /**
     * @notice Raised when fee-on-transfer behavior is unsupported for the operation.
     */
    error FeeOnTransferNotSupported();

    /**
     * @notice Raised when trying to add a plugin that is already configured.
     */
    error DuplicatePlugin();

    /**
     * @notice Raised when plugin allocation exceeds or conflicts with limits.
     */
    error PluginAllocated();

    /**
     * @notice Raised when plugin count exceeds the configured maximum.
     */
    error TooManyPlugins();

    /**
     * @notice Raised when migration-dependent actions are called before migration completion.
     */
    error MigrationNotCompleted();

    /**
     * @notice Raised when trying to whitelist a depositor that is already whitelisted.
     */
    error DuplicateDepositor();

    /**
     * @notice Raised when depositor address provided for whitelist initialization is invalid.
     */
    error InvalidDepositorToWhitelist();

    /* STRUCTS */

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param name Name of the vault.
     * @param symbol Symbol of the vault.
     * @param collateral Vault's underlying collateral.
     * @param burner Vault's burner to issue debt to (e.g., 0xdEaD or some unwrapper contract).
     * @param epochDuration Duration of the vault epoch (it determines sync points for withdrawals).
     * @param depositWhitelist If enabling deposit whitelist.
     * @param depositorToWhitelist Initial depositor address to whitelist.
     * @param isDepositLimit If enabling deposit limit.
     * @param depositLimit Deposit limit (maximum amount of the collateral that can be in the vault simultaneously).
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param depositWhitelistSetRoleHolder Address of the initial DEPOSIT_WHITELIST_SET_ROLE holder.
     * @param depositorWhitelistRoleHolder Address of the initial DEPOSITOR_WHITELIST_ROLE holder.
     * @param isDepositLimitSetRoleHolder Address of the initial IS_DEPOSIT_LIMIT_SET_ROLE holder.
     * @param depositLimitSetRoleHolder Address of the initial DEPOSIT_LIMIT_SET_ROLE holder.
     * @param setPluginLimitRoleHolder Address of the initial SET_PLUGIN_LIMIT_ROLE holder.
     * @param allocatePluginRoleHolder Address of the initial ALLOCATE_PLUGIN_ROLE holder.
     * @param pluginsData Initial plugin list.
     */
    struct InitParams {
        string name;
        string symbol;
        address collateral;
        address burner;
        uint48 epochDuration;
        bool depositWhitelist;
        address depositorToWhitelist;
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
     * @param name Name of the vault.
     * @param symbol Symbol of the vault.
     * @param delegatorParams Parameters for the delegator migration.
     * @param slasherParams Parameters for the slasher migration.
     */
    struct MigrateParams {
        string name;
        string symbol;
        bytes delegatorParams;
        bytes slasherParams;
    }

    /**
     * @notice Plugin configuration entry for initialization.
     * @param plugin Address of the plugin.
     * @param limit Allocation limit for the plugin.
     */
    struct PluginData {
        address plugin;
        uint208 limit;
    }

    /* EVENTS */

    /**
     * @notice Emitted when a deposit is made.
     * @param depositor Account that made the deposit.
     * @param onBehalfOf Account the deposit was made on behalf of.
     * @param amount Amount of the collateral deposited.
     * @param shares Amount of the active shares minted.
     */
    event Deposit(address indexed depositor, address indexed onBehalfOf, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is made.
     * @param withdrawer Account that made the withdrawal.
     * @param claimer Account that needs to claim the withdrawal.
     * @param amount Amount of the collateral withdrawn.
     * @param burnedShares Amount of the active shares burned.
     * @param mintedShares Amount of the epoch withdrawal shares minted.
     */
    event Withdraw(
        address indexed withdrawer, address indexed claimer, uint256 amount, uint256 burnedShares, uint256 mintedShares
    );

    /**
     * @notice Emitted when an instant withdrawal is made.
     * @param recipient Account that received the collateral.
     * @param amount Amount of the collateral withdrawn.
     */
    event InstantWithdraw(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a claim is made.
     * @param claimer Account that claimed.
     * @param recipient Account that received the collateral.
     * @param index Index the collateral was claimed for.
     * @param amount Amount of the collateral claimed.
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 index, uint256 amount);

    /**
     * @notice Emitted when a batch claim is made.
     * @param claimer Account that claimed.
     * @param recipient Account that received the collateral.
     * @param indexes Indexes the collateral was claimed for.
     * @param amount Amount of the collateral claimed.
     */
    event ClaimBatch(address indexed claimer, address indexed recipient, uint256[] indexes, uint256 amount);

    /**
     * @notice Emitted when collateral is donated into vault accounting.
     * @param amount Donated collateral amount.
     */
    event Donate(uint256 amount);

    /**
     * @notice Emitted when a slash happens.
     * @param amount Amount of the collateral to slash.
     * @param slashedAmount Real amount of the collateral slashed.
     */
    event OnSlash(uint256 amount, uint256 slashedAmount);

    /**
     * @notice Emitted when a deposit whitelist status is enabled/disabled.
     * @param status If enabled deposit whitelist.
     */
    event SetDepositWhitelist(bool status);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account Account for which the whitelist status is set.
     * @param status If whitelisted the account.
     */
    event SetDepositorWhitelistStatus(address indexed account, bool status);

    /**
     * @notice Emitted when a deposit limit status is enabled/disabled.
     * @param status If enabled deposit limit.
     */
    event SetIsDepositLimit(bool status);

    /**
     * @notice Emitted when a deposit limit is set.
     * @param limit Deposit limit (maximum amount of the collateral that can be in the vault simultaneously).
     */
    event SetDepositLimit(uint256 limit);

    /**
     * @notice Emitted when a limit is set.
     * @param plugin Address of the plugin.
     * @param limit Limit of the plugin.
     */
    event SetPluginLimit(address indexed plugin, uint208 limit);

    /**
     * @notice Emitted when a plugin is swapped.
     * @param plugin1 Address of the first plugin.
     * @param plugin2 Address of the second plugin.
     */
    event SwapPlugins(address indexed plugin1, address indexed plugin2);

    /**
     * @notice Emitted when collateral is allocated to a plugin.
     * @param plugin Address of the plugin.
     * @param amount Allocated amount.
     */
    event Allocate(address indexed plugin, uint256 amount);

    /**
     * @notice Emitted when collateral is deallocated from a plugin.
     * @param plugin Address of the plugin.
     * @param amount Deallocated amount.
     */
    event Deallocate(address indexed plugin, uint256 amount);

    /**
     * @notice Emitted when a slashing is synced.
     * @param amount Amount of the collateral to slash.
     */
    event SyncOwedSlash(uint256 amount);

    /**
     * @notice Emitted when a delegator is set.
     * @param delegator Vault's delegator to delegate the stake to networks and operators.
     * @dev Can be set only once.
     */
    event SetDelegator(address indexed delegator);

    /**
     * @notice Emitted when a slasher is set.
     * @param slasher Vault's slasher to provide a slashing mechanism to networks.
     * @dev Can be set only once.
     */
    event SetSlasher(address indexed slasher);

    /**
     * @notice Emitted when a vault is initialized.
     * @param params Initial parameters for the vault.
     */
    event Initialize(InitParams params);

    /**
     * @notice Emitted when a vault is migrated.
     * @param params Initial parameters for the vault.
     * @param newDelegator Address of the new delegator.
     * @param newSlasher Address of the new slasher.
     */
    event Migrate(MigrateParams params, address newDelegator, address newSlasher);

    /* FUNCTIONS */

    /**
     * @notice Execute a batch of delegatecalls on the vault.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Check if the vault is fully initialized (a delegator and a slasher are set).
     * @return If The vault is fully initialized.
     */
    function isInitialized() external view returns (bool);

    /**
     * @notice Get a total amount of the collateral that can be slashed.
     * @return Total Amount of the slashable collateral.
     */
    function totalStake() external view returns (uint256);

    /**
     * @notice Get a total amount of the active withdrawals for a given duration at a given timestamp.
     * @param duration Duration to get the active withdrawals for.
     * @param timestamp Time point to get the active withdrawals at.
     * @return Total Amount of the active withdrawals.
     */
    function activeWithdrawalsForAt(uint48 duration, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get a total amount of the active withdrawals for a given duration.
     * @param duration Duration to get the active withdrawals for.
     * @return Total Amount of the active withdrawals.
     */
    function activeWithdrawalsFor(uint48 duration) external view returns (uint256);

    /**
     * @notice Get a total amount of the active withdrawals at a given timestamp.
     * @param timestamp Time point to get the active withdrawals at.
     * @return Total Amount of the active withdrawals.
     */
    function activeWithdrawalsAt(uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get the current amount of active withdrawals.
     * @return Total Amount of active withdrawals.
     */
    function activeWithdrawals() external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account at a given timestamp.
     * @param account Account to get the active balance for.
     * @param timestamp Time point to get the active balance for the account at.
     * @param hints Reserved hints payload for compatibility.
     * @return Active Balance for the account at the timestamp.
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes memory hints) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account Account to get the active balance for.
     * @return Active Balance for the account.
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get how many withdrawals a particular account requested.
     * @param account Account to check the withdrawals for.
     * @return The Number of withdrawals requested by the account.
     */
    function withdrawalsOfLength(address account) external view returns (uint256);

    /**
     * @notice Get a number of withdrawal shares for a particular account at a given index (zero if claimed).
     * @param index Index to get the number of withdrawal shares for the account at.
     * @param account Account to get the number of withdrawal shares for.
     * @return Number Of withdrawal shares for the account at the index.
     */
    function withdrawalSharesOf(uint256 index, address account) external view returns (uint256);

    /**
     * @notice Get when the withdrawal becomes claimable for a particular account at a given index.
     * @param index Index to check the withdrawals for the account at.
     * @param account Account to check the withdrawal for.
     * @return When The withdrawal is claimable for the account at the index.
     */
    function withdrawalUnlockAfter(uint256 index, address account) external view returns (uint48);

    /**
     * @notice Get withdrawals for a particular account at a given index (zero if claimed).
     * @param index Index to get the withdrawals for the account at.
     * @param account Account to get the withdrawals for.
     * @return Withdrawals For the account at the index.
     */
    function withdrawalsOf(uint256 index, address account) external view returns (uint256);

    /**
     * @notice Get the amount that can still be allocated into plugins.
     * @return Allocatable Amount of collateral.
     */
    function allocatable() external view returns (uint256);

    /**
     * @notice Deposit collateral into the vault.
     * @param onBehalfOf Account the deposit is made on behalf of.
     * @param amount Amount of the collateral to deposit.
     * @return depositedAmount Real amount of the collateral deposited.
     * @return mintedShares Amount of the active shares minted.
     */
    function deposit(address onBehalfOf, uint256 amount)
        external
        returns (uint256 depositedAmount, uint256 mintedShares);

    /**
     * @notice Withdraw collateral from the vault (it will be claimable after the next epoch).
     * @param claimer Account that needs to claim the withdrawal.
     * @param amount Amount of the collateral to withdraw.
     * @return burnedShares Amount of the active shares burned.
     * @return mintedShares Amount of the epoch withdrawal shares minted.
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);

    /**
     * @notice Redeem collateral from the vault (it will be claimable after the next epoch).
     * @param claimer Account that needs to claim the withdrawal.
     * @param shares Amount of the active shares to redeem.
     * @return withdrawnAssets Amount of the collateral withdrawn.
     * @return mintedShares Amount of the epoch withdrawal shares minted.
     */
    function redeem(address claimer, uint256 shares) external returns (uint256 withdrawnAssets, uint256 mintedShares);

    /**
     * @notice Instant withdraw collateral from the vault.
     * @param recipient Account that received the collateral.
     * @param amount Amount of the collateral withdrawn.
     * @return withdrawnAssets Amount of collateral withdrawn.
     * @return burnedShares Amount of active shares burned.
     */
    function instantWithdraw(address recipient, uint256 amount)
        external
        returns (uint256 withdrawnAssets, uint256 burnedShares);

    /**
     * @notice Claim collateral from the vault.
     * @param recipient Account that receives the collateral.
     * @param index Index to claim the collateral for.
     * @return amount Amount of the collateral claimed.
     */
    function claim(address recipient, uint256 index) external returns (uint256 amount);

    /**
     * @notice Claim collateral from the vault for multiple indexes.
     * @param recipient Account that receives the collateral.
     * @param indexes Indexes to claim the collateral for.
     * @return amount Amount of the collateral claimed.
     */
    function claimBatch(address recipient, uint256[] calldata indexes) external returns (uint256 amount);

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status If enabling deposit whitelist.
     * @dev Only a DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account Account for which the whitelist status is set.
     * @param status If whitelisting the account.
     * @dev Only a DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;

    /**
     * @notice Enable/disable deposit limit.
     * @param status If enabling deposit limit.
     * @dev Only a IS_DEPOSIT_LIMIT_SET_ROLE holder can call this function.
     */
    function setIsDepositLimit(bool status) external;

    /**
     * @notice Set a deposit limit.
     * @param limit Deposit limit (maximum amount of the collateral that can be in the vault simultaneously).
     * @dev Only a DEPOSIT_LIMIT_SET_ROLE holder can call this function.
     */
    function setDepositLimit(uint256 limit) external;

    /**
     * @notice Set a plugin limit.
     * @param plugin Address of the plugin.
     * @param limit Limit of the plugin.
     * @dev Only a SET_PLUGIN_LIMIT_ROLE holder can call this function.
     */
    function setPluginLimit(address plugin, uint208 limit) external;

    /**
     * @notice Swap plugin order.
     * @param plugin1 Address of the first plugin.
     * @param plugin2 Address of the second plugin.
     * @dev Only a SWAP_PLUGINS_ROLE holder can call this function.
     */
    function swapPlugins(address plugin1, address plugin2) external;

    /**
     * @notice Allocate collateral to the plugin.
     * @param plugin Address of the plugin.
     * @param amount Amount of collateral to allocate.
     * @return allocated Amount of collateral allocated.
     * @dev Only an ALLOCATE_PLUGIN_ROLE holder can call this function.
     */
    function allocatePlugin(address plugin, uint256 amount) external returns (uint256 allocated);

    /**
     * @notice Deallocate collateral from the plugin.
     * @param plugin Address of the plugin.
     * @param amount Amount of collateral to deallocate.
     * @return deallocated Amount of collateral deallocated.
     * @dev Only a DEALLOCATE_PLUGIN_ROLE holder can call this function.
     */
    function deallocatePlugin(address plugin, uint256 amount) external returns (uint256 deallocated);

    /**
     * @notice Skim rewards from plugins into the vault.
     */
    function skimPlugins() external;

    /**
     * @notice Deallocate collateral from plugins when needed.
     */
    function deallocatePlugins() external;
}
