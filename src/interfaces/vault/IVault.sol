// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IVaultStorage} from "./IVaultStorage.sol";

uint64 constant VAULT_VERSION = 1;

/**
 * @title IVault
 * @notice Interface for the Vault contract.
 */
interface IVault is IMigratableEntity, IVaultStorage {
    error AlreadyClaimed();
    error AlreadySet();
    error DelegatorAlreadyInitialized();
    error DepositLimitReached();
    error InsufficientClaim();
    error InsufficientDeposit();
    error InsufficientRedemption();
    error InsufficientWithdrawal();
    error InvalidAccount();
    error InvalidCaptureEpoch();
    error InvalidClaimer();
    error InvalidCollateral();
    error InvalidDelegator();
    error InvalidEpoch();
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

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param collateral Vault's underlying collateral.
     * @param burner Vault's burner to issue debt to (e.g., 0xdEaD or some unwrapper contract).
     * @param epochDuration Duration of the vault epoch (it determines sync points for withdrawals).
     * @param depositWhitelist If enabling deposit whitelist.
     * @param isDepositLimit If enabling deposit limit.
     * @param depositLimit Deposit limit (maximum amount of the collateral that can be in the vault simultaneously).
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param depositWhitelistSetRoleHolder Address of the initial DEPOSIT_WHITELIST_SET_ROLE holder.
     * @param depositorWhitelistRoleHolder Address of the initial DEPOSITOR_WHITELIST_ROLE holder.
     * @param isDepositLimitSetRoleHolder Address of the initial IS_DEPOSIT_LIMIT_SET_ROLE holder.
     * @param depositLimitSetRoleHolder Address of the initial DEPOSIT_LIMIT_SET_ROLE holder.
     */
    struct InitParams {
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
     * @notice Hints for an active balance.
     * @param activeSharesOfHint Hint for the active shares of checkpoint.
     * @param activeStakeHint Hint for the active stake checkpoint.
     * @param activeSharesHint Hint for the active shares checkpoint.
     */
    struct ActiveBalanceOfHints {
        bytes activeSharesOfHint;
        bytes activeStakeHint;
        bytes activeSharesHint;
    }

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
     * @notice Emitted when a claim is made.
     * @param claimer Account that claimed.
     * @param recipient Account that received the collateral.
     * @param epoch Epoch the collateral was claimed for.
     * @param amount Amount of the collateral claimed.
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 epoch, uint256 amount);

    /**
     * @notice Emitted when a batch claim is made.
     * @param claimer Account that claimed.
     * @param recipient Account that received the collateral.
     * @param epochs Epochs the collateral was claimed for.
     * @param amount Amount of the collateral claimed.
     */
    event ClaimBatch(address indexed claimer, address indexed recipient, uint256[] epochs, uint256 amount);

    /**
     * @notice Emitted when a slash happens.
     * @param amount Amount of the collateral to slash.
     * @param captureTimestamp Time point when the stake was captured.
     * @param slashedAmount Real amount of the collateral slashed.
     */
    event OnSlash(uint256 amount, uint48 captureTimestamp, uint256 slashedAmount);

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
     * @notice Get an active balance for a particular account at a given timestamp using hints.
     * @param account Account to get the active balance for.
     * @param timestamp Time point to get the active balance for the account at.
     * @param hints Hints for checkpoints' indexes.
     * @return Active Balance for the account at the timestamp.
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes calldata hints) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account Account to get the active balance for.
     * @return Active Balance for the account.
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get withdrawals for a particular account at a given epoch (zero if claimed).
     * @param epoch Epoch to get the withdrawals for the account at.
     * @param account Account to get the withdrawals for.
     * @return Withdrawals For the account at the epoch.
     */
    function withdrawalsOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Get a total amount of the collateral that can be slashed for a given account.
     * @param account Account to get the slashable collateral for.
     * @return Total Amount of the account's slashable collateral.
     */
    function slashableBalanceOf(address account) external view returns (uint256);

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
     * @notice Claim collateral from the vault.
     * @param recipient Account that receives the collateral.
     * @param epoch Epoch to claim the collateral for.
     * @return amount Amount of the collateral claimed.
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount);

    /**
     * @notice Claim collateral from the vault for multiple epochs.
     * @param recipient Account that receives the collateral.
     * @param epochs Epochs to claim the collateral for.
     * @return amount Amount of the collateral claimed.
     */
    function claimBatch(address recipient, uint256[] calldata epochs) external returns (uint256 amount);

    /**
     * @notice Slash callback for burning collateral.
     * @param amount Amount to slash.
     * @param captureTimestamp Time point when the stake was captured.
     * @return slashedAmount Real amount of the collateral slashed.
     * @dev Only the slasher can call this function.
     */
    function onSlash(uint256 amount, uint48 captureTimestamp) external returns (uint256 slashedAmount);

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
     * @notice Set a delegator.
     * @param delegator Vault's delegator to delegate the stake to networks and operators.
     * @dev Can be set only once.
     */
    function setDelegator(address delegator) external;

    /**
     * @notice Set a slasher.
     * @param slasher Vault's slasher to provide a slashing mechanism to networks.
     * @dev Can be set only once.
     */
    function setSlasher(address slasher) external;
}
