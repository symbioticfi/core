// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IVaultStorage} from "./IVaultStorage.sol";

interface IVault is IVaultStorage {
    error AlreadyClaimed();
    error AlreadySet();
    error InsufficientClaim();
    error InsufficientDeposit();
    error InsufficientWithdrawal();
    error InvalidAccount();
    error InvalidClaimer();
    error InvalidCollateral();
    error InvalidEpoch();
    error InvalidEpochDuration();
    error InvalidOnBehalfOf();
    error InvalidRecipient();
    error NoDepositWhitelist();
    error NotWhitelistedDepositor();
    error NotSlasher();
    error TooMuchWithdraw();
    error InvalidSlasherSetEpochsDelay();
    error NotDelegator();
    error TooMuchSlash();
    error InvalidCaptureEpoch();

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param collateral vault's underlying collateral
     * @param delegator vault's delegator to delegate the stake to networks and operators
     * @param slasher vault's slasher to provide a slashing mechanism to networks
     * @param burner vault's burner to issue debt to (e.g. 0xdEaD or some unwrapper contract)
     * @param epochDuration duration of the vault epoch (it determines sync points for withdrawals)
     * @param slasherSetEpochsDelay delay in epochs to set a new slasher
     * @param depositWhitelist if enabling deposit whitelist
     * @param defaultAdminRoleHolder address of the initial DEFAULT_ADMIN_ROLE holder
     * @param slasherSetRoleHolder address of the initial SLASHER_SET_ROLE holder
     * @param depositorWhitelistRoleHolder address of the initial DEPOSITOR_WHITELIST_ROLE holder
     */
    struct InitParams {
        address collateral;
        address delegator;
        address slasher;
        address burner;
        uint48 epochDuration;
        uint256 slasherSetEpochsDelay;
        bool depositWhitelist;
        address defaultAdminRoleHolder;
        address slasherSetRoleHolder;
        address depositorWhitelistRoleHolder;
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
     * @param amount amount of the collateral claimed
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a slash happened.
     * @param slasher address of the slasher
     * @param slashedAmount amount of the collateral slashed
     */
    event OnSlash(address indexed slasher, uint256 slashedAmount);

    /**
     * @notice Emitted when a slasher is set (it provides networks a slashing mechanism).
     * @param slasher address of the slasher
     */
    event SetSlasher(address slasher);

    /**
     * @notice Emitted when a deposit whitelist status is enabled/disabled.
     * @param depositWhitelist if enabled deposit whitelist
     */
    event SetDepositWhitelist(bool depositWhitelist);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account account for which the whitelist status is set
     * @param status if whitelisted the account
     */
    event SetDepositorWhitelistStatus(address indexed account, bool status);

    /**
     * @notice Get a slasher in `duration` seconds (it provides networks a slashing mechanism).
     * @return address of the slasher in `duration` seconds
     */
    function slasherIn(uint48 duration) external view returns (address);

    /**
     * @notice Get a slasher (it provides networks a slashing mechanism).
     * @return address of the slasher
     */
    function slasher() external view returns (address);

    /**
     * @notice Get a total amount of the collateral that can be slashed
     *         in `duration` seconds (if there will be no new deposits and slash executions).
     * @param duration duration to get the total amount of the slashable collateral in
     * @return total amount of the slashable collateral in `duration` seconds
     * @dev The result can be manipulated by the withdrawals if `epochAt(Time.timestamp() + duration) > currentEpoch() + 1`.
     */
    function totalSupplyIn(uint48 duration) external view returns (uint256);

    /**
     * @notice Get a total amount of the collateral that can be slashed.
     * @return total amount of the slashable collateral
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account at a given timestamp.
     * @param account account to get the active balance for
     * @param timestamp time point to get the active balance for the account at
     * @return active balance for the account at the timestamp
     */
    function activeBalanceOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account account to get the active balance for
     * @return active balance for the account
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get withdrawals for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the withdrawals for the account at
     * @param account account to get the withdrawals for
     * @return withdrawals for the account at the epoch
     */
    function withdrawalsOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Deposit collateral into the vault.
     * @param onBehalfOf account the deposit is made on behalf of
     * @param amount amount of the collateral to deposit
     * @return shares amount of the active shares minted
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw collateral from the vault (it will be claimable after the next epoch).
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral to withdraw
     * @return burnedShares amount of the active shares burned
     * @return mintedShares amount of the epoch withdrawal shares minted
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);

    /**
     * @notice Claim collateral from the vault.
     * @param recipient account that receives the collateral
     * @param epoch epoch to claim the collateral for
     * @return amount amount of the collateral claimed
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount);

    /**
     * @notice Slash callback for burning collateral.
     * @param slashedAmount amount to slash
     * @param captureTimestamp time point when the stake was captured
     * @dev Only the slasher can call this function.
     */
    function onSlash(uint256 slashedAmount, uint48 captureTimestamp) external;

    /**
     * @notice Set a slasher (it provides networks a slashing mechanism).
     * @param slasher address of the slasher
     * @dev Only the SLASHER_SET_ROLE holder can call this function.
     */
    function setSlasher(address slasher) external;

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status if enabling deposit whitelist
     * @dev Only the DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account account for which the whitelist status is set
     * @param status if whitelisting the account
     * @dev Only the DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;
}
