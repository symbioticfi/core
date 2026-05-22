// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

uint64 constant VAULT_V2_VERSION = 3;

// keccak256("DEPOSIT_WHITELIST_SET_ROLE")
bytes32 constant DEPOSIT_WHITELIST_SET_ROLE = 0xbae4ee3de6c709ff9a002e774c5b78cb381560b219213c88ae0f1e207c03c023;
// keccak256("DEPOSITOR_WHITELIST_ROLE")
bytes32 constant DEPOSITOR_WHITELIST_ROLE = 0x9c56d972d63cbb4195b3c1484691dfc220fa96a4c47e7b6613bd82a022029e06;
// keccak256("IS_DEPOSIT_LIMIT_SET_ROLE")
bytes32 constant IS_DEPOSIT_LIMIT_SET_ROLE = 0xc6aaadd7371d5e8f9ed6849dd66a66573a3ba37167d03f4352c9ba5693678fac;
// keccak256("DEPOSIT_LIMIT_SET_ROLE")
bytes32 constant DEPOSIT_LIMIT_SET_ROLE = 0x4a634bc14d77baf979756509ef4298c6f6318af357828612545267ee2eb79233;
uint256 constant WAD = 1e18;

uint8 constant DECIMALS_OFFSET = 6;

/**
 * @title IVaultV2
 * @notice Interface for the VaultV2 contract.
 * @dev VaultV2 supports standard ERC20 collateral only; fee-on-transfer, rebasing, and other nonstandard balance-changing assets are unsupported.
 */
interface IVaultV2 is IMigratableEntity, IERC4626 {
    /* ERRORS */

    /**
     * @notice Raised when delegator initialization is attempted more than once.
     */
    error DelegatorAlreadyInitialized();

    /**
     * @notice Raised when a deposit would exceed the configured deposit limit.
     */
    error DepositLimitReached();

    /**
     * @notice Raised when the vault does not have enough free assets for the operation.
     */
    error InsufficientFreeAssets();

    /**
     * @notice Raised when an address argument is invalid.
     */
    error InvalidAddress();

    /**
     * @notice Raised when collateral address is invalid.
     */
    error InvalidCollateral();

    /**
     * @notice Raised when delegator address is invalid.
     */
    error InvalidDelegator();

    /**
     * @notice Raised when depositor address provided for whitelist initialization is invalid.
     */
    error InvalidDepositorToWhitelist();

    /**
     * @notice Raised when the caller is not the configured delegator.
     */
    error NotDelegator();

    /**
     * @notice Raised when depositor is not in the whitelist while whitelist is enabled.
     */
    error NotWhitelistedDepositor();

    /**
     * @notice Raised when the caller is not the configured withdrawal queue.
     */
    error NotWithdrawalQueue();

    /* STRUCTS */

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param name Name of the vault share token.
     * @param symbol Symbol of the vault share token.
     * @param asset Vault's underlying collateral asset.
     * @param burner Vault's burner hook target.
     * @param depositWhitelist Whether the deposit whitelist is enabled.
     * @param depositorToWhitelist Initial depositor address to whitelist.
     * @param isDepositLimit Whether the deposit limit is enabled.
     * @param depositLimit Deposit limit.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param depositWhitelistSetRoleHolder Address of the initial DEPOSIT_WHITELIST_SET_ROLE holder.
     * @param depositorWhitelistRoleHolder Address of the initial DEPOSITOR_WHITELIST_ROLE holder.
     * @param isDepositLimitSetRoleHolder Address of the initial IS_DEPOSIT_LIMIT_SET_ROLE holder.
     * @param depositLimitSetRoleHolder Address of the initial DEPOSIT_LIMIT_SET_ROLE holder.
     */
    struct InitParams {
        string name;
        string symbol;
        address asset;
        address burner;
        bool depositWhitelist;
        address depositorToWhitelist;
        bool isDepositLimit;
        uint256 depositLimit;
        address defaultAdminRoleHolder;
        address depositWhitelistSetRoleHolder;
        address depositorWhitelistRoleHolder;
        address isDepositLimitSetRoleHolder;
        address depositLimitSetRoleHolder;
    }

    /* EVENTS */

    /**
     * @notice Emitted when a withdrawal queue request is claimed through the vault.
     * @param claimer Account that claimed.
     * @param receiver Account that receives the collateral.
     * @param tokenId Withdrawal queue token id.
     * @param assets Amount of collateral claimed.
     */
    event Claim(address indexed claimer, address indexed receiver, uint256 tokenId, uint256 assets);

    /**
     * @notice Emitted when fee shares are accrued.
     * @param newTotalAssets Total assets after the accounting update.
     * @param performanceFeeShares Shares minted to the performance fee recipient.
     * @param managementFeeShares Shares minted to the management fee recipient.
     */
    event AccrueInterest(uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);

    /**
     * @notice Emitted when the delegator pulls liquid collateral out of the vault.
     * @param assets Amount pulled.
     * @param receiver Account that received the collateral.
     */
    event Pull(uint256 assets, address indexed receiver);

    /**
     * @notice Emitted when the delegator pushes liquid collateral into the vault.
     * @param assets Amount pushed.
     * @param owner Account that supplied the collateral.
     */
    event Push(uint256 assets, address indexed owner);

    /**
     * @notice Emitted when a deposit whitelist status is enabled or disabled.
     * @param status Whether the deposit whitelist is enabled.
     */
    event SetDepositWhitelist(bool status);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account Account for which the whitelist status is set.
     * @param status Whether the account is whitelisted.
     */
    event SetDepositorWhitelistStatus(address indexed account, bool status);

    /**
     * @notice Emitted when a deposit limit status is enabled or disabled.
     * @param status Whether the deposit limit is enabled.
     */
    event SetIsDepositLimit(bool status);

    /**
     * @notice Emitted when a deposit limit is set.
     * @param limit Deposit limit.
     */
    event SetDepositLimit(uint256 limit);

    /**
     * @notice Emitted when a delegator is set.
     * @param delegator Vault's delegator.
     * @dev Can be set only once.
     */
    event SetDelegator(address indexed delegator);

    /**
     * @notice Emitted when a vault is initialized.
     * @param params Initial parameters for the vault.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Get the vault's underlying collateral asset.
     * @return asset Address of the underlying collateral.
     */
    function collateral() external view returns (address asset);

    /**
     * @notice Get the burner used by the vault's slashing flow.
     * @return burnerAddress Address of the burner.
     */
    function burner() external view returns (address burnerAddress);

    /**
     * @notice Get the delegator associated with the vault.
     * @return delegatorAddress Address of the delegator.
     */
    function delegator() external view returns (address delegatorAddress);

    /**
     * @notice Get the withdrawal queue associated with the vault.
     * @return withdrawalQueueAddress Address of the withdrawal queue.
     */
    function withdrawalQueue() external view returns (address withdrawalQueueAddress);

    /**
     * @notice Get whether the deposit whitelist is enabled.
     * @return enabled Whether the deposit whitelist is enabled.
     */
    function depositWhitelist() external view returns (bool enabled);

    /**
     * @notice Get whether the deposit limit is enabled.
     * @return enabled Whether the deposit limit is enabled.
     */
    function isDepositLimit() external view returns (bool enabled);

    /**
     * @notice Get the configured deposit limit.
     * @return limit Deposit limit.
     */
    function depositLimit() external view returns (uint256 limit);

    /**
     * @notice Get the performance fee used by the latest accrual snapshot.
     * @return fee Last performance fee in WAD.
     */
    function lastPerformanceFee() external view returns (uint96 fee);

    /**
     * @notice Get the management fee used by the latest accrual snapshot.
     * @return fee Last management fee per second in WAD.
     */
    function lastManagementFee() external view returns (uint96 fee);

    /**
     * @notice Get the last timestamp when fees were accrued.
     * @return timestamp Last fee accrual timestamp.
     */
    function lastUpdate() external view returns (uint48 timestamp);

    /**
     * @notice Get whether an account is whitelisted as a depositor.
     * @param account Address to check.
     * @return whitelisted Whether the account is whitelisted.
     */
    function isDepositorWhitelisted(address account) external view returns (bool whitelisted);

    /**
     * @notice Get total active shares at a timestamp using a checkpoint hint.
     * @param timestamp Timestamp to read.
     * @param hint Checkpoint hint.
     * @return shares Total active shares at the timestamp.
     */
    function activeSharesAt(uint48 timestamp, bytes calldata hint) external view returns (uint256 shares);

    /**
     * @notice Get current total active shares.
     * @return shares Current total active shares.
     */
    function activeShares() external view returns (uint256 shares);

    /**
     * @notice Get current active stake.
     * @return amount Current active stake.
     */
    function activeStake() external view returns (uint256 amount);

    /**
     * @notice Get total slashable stake.
     * @return amount Total slashable stake.
     */
    function totalStake() external view returns (uint256 amount);

    /**
     * @notice Get active shares for an account at a timestamp using a checkpoint hint.
     * @param account Account to read.
     * @param timestamp Timestamp to read.
     * @param hint Checkpoint hint.
     * @return shares Active shares for the account at the timestamp.
     */
    function activeSharesOfAt(address account, uint48 timestamp, bytes calldata hint)
        external
        view
        returns (uint256 shares);

    /**
     * @notice Get current active shares for an account.
     * @param account Account to read.
     * @return shares Current active shares for the account.
     */
    function activeSharesOf(address account) external view returns (uint256 shares);

    /**
     * @notice Execute a batch of delegatecalls on the vault.
     * @param data Calldata items to execute.
     */
    function multicall(bytes[] calldata data) external;

    /**
     * @notice Check if the vault is initialized.
     * @return initialized Whether the vault is initialized.
     */
    function isInitialized() external view returns (bool initialized);

    /**
     * @notice Get total assets tracked by the vault.
     * @return assets Vault liquid balance plus delegator-managed assets.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Get an active balance for an account.
     * @param account Account to get the active balance for.
     * @return balance Active balance for the account.
     */
    function activeBalanceOf(address account) external view returns (uint256 balance);

    /**
     * @notice View total assets and fee shares that would be accrued at the current timestamp.
     * @return newTotalAssets Total assets after the accounting update.
     * @return performanceFeeShares Shares that would be minted to the performance fee recipient.
     * @return managementFeeShares Shares that would be minted to the management fee recipient.
     */
    function getAccrueInterest()
        external
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);

    /**
     * @notice Accrue performance and management fees using the latest known total assets.
     * @return performanceFeeShares Shares minted to the performance fee recipient.
     * @return managementFeeShares Shares minted to the management fee recipient.
     */
    function accrueInterest() external returns (uint256 performanceFeeShares, uint256 managementFeeShares);

    /**
     * @notice Pull liquid collateral from the vault to a receiver.
     * @param assets Amount of collateral to pull.
     * @param receiver Account that receives the collateral.
     * @dev Only the configured delegator can call this function.
     */
    function pull(uint256 assets, address receiver) external;

    /**
     * @notice Push liquid collateral from an owner into the vault.
     * @param assets Amount of collateral to push.
     * @param owner Account that supplies the collateral.
     * @dev Only the configured delegator can call this function.
     */
    function push(uint256 assets, address owner) external;

    /**
     * @notice Get liquid collateral currently held by the vault.
     * @return assets Liquid asset balance.
     */
    function freeAssets() external view returns (uint256 assets);

    /**
     * @notice Enable or disable deposit whitelist.
     * @param status Whether to enable deposit whitelist.
     * @dev Only a DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account Account for which the whitelist status is set.
     * @param status Whether to whitelist the account.
     * @dev Only a DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;

    /**
     * @notice Enable or disable deposit limit.
     * @param status Whether to enable deposit limit.
     * @dev Only an IS_DEPOSIT_LIMIT_SET_ROLE holder can call this function.
     */
    function setIsDepositLimit(bool status) external;

    /**
     * @notice Set a deposit limit.
     * @param limit Deposit limit.
     * @dev Only a DEPOSIT_LIMIT_SET_ROLE holder can call this function.
     */
    function setDepositLimit(uint256 limit) external;
}
