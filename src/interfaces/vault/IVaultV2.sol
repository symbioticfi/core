// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMigratableEntity} from "../common/IMigratableEntity.sol";
import {IMulticallable} from "../common/IMulticallable.sol";

uint64 constant VAULT_V2_VERSION = 3;

// keccak256("MANAGEMENT_FEE_ROLE")
bytes32 constant MANAGEMENT_FEE_ROLE = 0x75c709b3ee540481221bc7e0e2078bc69971d591109706c28c3cb1540b251bc1;
// keccak256("PERFORMANCE_FEE_ROLE")
bytes32 constant PERFORMANCE_FEE_ROLE = 0x7d60a5b727427c7c190f6811f2a84845a230233579ff66ee989bfff75d300871;
// keccak256("DEPOSIT_LIMIT_SET_ROLE")
bytes32 constant DEPOSIT_LIMIT_SET_ROLE = 0x4a634bc14d77baf979756509ef4298c6f6318af357828612545267ee2eb79233;
// keccak256("DEPOSITOR_WHITELIST_ROLE")
bytes32 constant DEPOSITOR_WHITELIST_ROLE = 0x9c56d972d63cbb4195b3c1484691dfc220fa96a4c47e7b6613bd82a022029e06;
// keccak256("IS_DEPOSIT_LIMIT_SET_ROLE")
bytes32 constant IS_DEPOSIT_LIMIT_SET_ROLE = 0xc6aaadd7371d5e8f9ed6849dd66a66573a3ba37167d03f4352c9ba5693678fac;
// keccak256("DEPOSIT_WHITELIST_SET_ROLE")
bytes32 constant DEPOSIT_WHITELIST_SET_ROLE = 0xbae4ee3de6c709ff9a002e774c5b78cb381560b219213c88ae0f1e207c03c023;

uint96 constant MAX_FEE = 1e18;
uint96 constant MAX_MANAGEMENT_FEE = 5e16 / uint96(365 days); // 5%
uint96 constant MAX_PERFORMANCE_FEE = 2e17; // 20%

uint8 constant SHARES_DECIMALS = 18;

/**
 * @title IVaultV2
 * @notice Interface for the VaultV2 contract.
 * @dev VaultV2 supports standard ERC20 assets only; fee-on-transfer, rebasing, and other nonstandard balance-changing assets are unsupported.
 */
interface IVaultV2 is IMigratableEntity, IMulticallable {
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
     * @notice Raised when a configured fee exceeds its maximum value.
     */
    error FeeTooHigh();

    /**
     * @notice Raised when the vault does not have enough free assets for the operation.
     */
    error InsufficientFreeAssets();

    /**
     * @notice Raised when an address argument is invalid.
     */
    error InvalidAddress();

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
     * @param asset Vault's underlying ERC4626 asset.
     * @param depositWhitelist Whether the deposit whitelist is enabled.
     * @param depositorToWhitelist Initial depositor address to whitelist.
     * @param depositLimit Deposit limit.
     * @param isDepositLimit Whether the deposit limit is enabled.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param managementFeeRoleHolder Address of the initial MANAGEMENT_FEE_ROLE holder.
     * @param performanceFeeRoleHolder Address of the initial PERFORMANCE_FEE_ROLE holder.
     * @param depositLimitSetRoleHolder Address of the initial DEPOSIT_LIMIT_SET_ROLE holder.
     * @param depositorWhitelistRoleHolder Address of the initial DEPOSITOR_WHITELIST_ROLE holder.
     * @param isDepositLimitSetRoleHolder Address of the initial IS_DEPOSIT_LIMIT_SET_ROLE holder.
     * @param depositWhitelistSetRoleHolder Address of the initial DEPOSIT_WHITELIST_SET_ROLE holder.
     */
    struct InitParams {
        string name;
        string symbol;
        address asset;
        bool depositWhitelist;
        address depositorToWhitelist;
        uint256 depositLimit;
        bool isDepositLimit;
        address defaultAdminRoleHolder;
        address managementFeeRoleHolder;
        address performanceFeeRoleHolder;
        address depositLimitSetRoleHolder;
        address depositorWhitelistRoleHolder;
        address isDepositLimitSetRoleHolder;
        address depositWhitelistSetRoleHolder;
    }

    /* EVENTS */

    /**
     * @notice Emitted when a withdrawal queue request is claimed through the vault.
     * @param claimer Account that claimed.
     * @param receiver Account that receives the assets.
     * @param tokenId Withdrawal queue token id.
     * @param assets Amount of assets claimed.
     */
    event Claim(address indexed claimer, address indexed receiver, uint256 tokenId, uint256 assets);

    /**
     * @notice Emitted when fee shares are accrued.
     * @param newTotalAssets Total assets after the accounting update.
     * @param managementFeeShares Shares minted to the management fee receiver.
     * @param performanceFeeShares Shares minted to the performance fee receiver.
     * @param protocolFeeShares Shares minted to the protocol fee receiver.
     */
    event AccrueInterest(
        uint256 newTotalAssets, uint256 managementFeeShares, uint256 performanceFeeShares, uint256 protocolFeeShares
    );

    /**
     * @notice Emitted when cached protocol fee config is updated.
     * @param receiver Protocol fee receiver.
     * @param managementFee Protocol management fee per second scaled by MAX_FEE.
     * @param performanceFee Protocol performance fee scaled by MAX_FEE.
     */
    event UpdateProtocolFee(address indexed receiver, uint96 managementFee, uint96 performanceFee);

    /**
     * @notice Emitted when the delegator pulls liquid assets out of the vault.
     * @param assets Amount pulled.
     * @param receiver Account that received the assets.
     */
    event Pull(uint256 assets, address indexed receiver);

    /**
     * @notice Emitted when the delegator pushes liquid assets into the vault.
     * @param assets Amount pushed.
     * @param owner Account that supplied the assets.
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
     * @notice Emitted when the management fee and receiver are set.
     * @param fee Management fee per second scaled by MAX_FEE.
     * @param receiver Management fee receiver.
     */
    event SetManagementFee(uint256 fee, address indexed receiver);

    /**
     * @notice Emitted when the performance fee and receiver are set.
     * @param fee Performance fee scaled by MAX_FEE.
     * @param receiver Performance fee receiver.
     */
    event SetPerformanceFee(uint256 fee, address indexed receiver);

    /**
     * @notice Emitted when a delegator is set.
     * @param delegator Vault's delegator.
     * @dev Can be set only once.
     */
    event SetDelegator(address indexed delegator);

    /**
     * @notice Emitted when the withdrawal queue is deployed and set.
     * @param withdrawalQueue Withdrawal queue address.
     */
    event SetWithdrawalQueue(address indexed withdrawalQueue);

    /**
     * @notice Emitted when a vault is initialized.
     * @param params Initial parameters for the vault.
     */
    event Initialize(InitParams params);

    /* FUNCTIONS */

    /**
     * @notice Get the delegator associated with the vault.
     * @return delegatorAddress Address of the delegator.
     */
    function delegator() external view returns (address delegatorAddress);

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
     * @notice Get whether the deposit whitelist is enabled.
     * @return enabled Whether the deposit whitelist is enabled.
     */
    function depositWhitelist() external view returns (bool enabled);

    /**
     * @notice Get the withdrawal queue associated with the vault.
     * @return withdrawalQueueAddress Address of the withdrawal queue.
     */
    function withdrawalQueue() external view returns (address withdrawalQueueAddress);

    /**
     * @notice Get whether an account is whitelisted as a depositor.
     * @param account Address to check.
     * @return whitelisted Whether the account is whitelisted.
     */
    function isDepositorWhitelisted(address account) external view returns (bool whitelisted);

    /**
     * @notice Get the last timestamp when fees were accrued.
     * @return timestamp Last fee accrual timestamp.
     */
    function lastUpdate() external view returns (uint48 timestamp);

    /**
     * @notice Get the management fee.
     * @return fee Management fee per second scaled by MAX_FEE.
     */
    function managementFee() external view returns (uint96 fee);

    /**
     * @notice Get the performance fee.
     * @return fee Performance fee scaled by MAX_FEE.
     */
    function performanceFee() external view returns (uint96 fee);

    /**
     * @notice Get the protocol management fee cached at the last fee accrual.
     * @return fee Cached protocol management fee per second scaled by MAX_FEE.
     */
    function lastProtocolManagementFee() external view returns (uint96 fee);

    /**
     * @notice Get the protocol performance fee cached at the last fee accrual.
     * @return fee Cached protocol performance fee scaled by MAX_FEE.
     */
    function lastProtocolPerformanceFee() external view returns (uint96 fee);

    /**
     * @notice Get the management fee receiver.
     * @return receiver Management fee receiver.
     */
    function managementFeeReceiver() external view returns (address receiver);

    /**
     * @notice Get the performance fee receiver.
     * @return receiver Performance fee receiver.
     */
    function performanceFeeReceiver() external view returns (address receiver);

    /**
     * @notice Get the protocol fee receiver cached at the last fee accrual.
     * @return receiver Cached protocol fee receiver.
     */
    function lastProtocolFeeReceiver() external view returns (address receiver);

    /**
     * @notice Check if the vault is initialized.
     * @return initialized Whether the vault is initialized.
     */
    function isInitialized() external view returns (bool initialized);

    /**
     * @notice Get total share supply at a given timestamp.
     * @param timestamp Time point to get total supply at.
     * @return supply Total share supply at the timestamp.
     */
    function totalSupplyAt(uint48 timestamp) external view returns (uint256 supply);

    /**
     * @notice Get an account share balance at a given timestamp.
     * @param account Account to get the balance for.
     * @param timestamp Time point to get the balance at.
     * @return balance Account share balance at the timestamp.
     */
    function balanceOfAt(address account, uint48 timestamp) external view returns (uint256 balance);

    /**
     * @notice View total assets and fee shares that would be accrued at the current timestamp.
     * @return newTotalAssets Total assets after the accounting update.
     * @return managementFeeShares Shares that would be minted to the management fee receiver.
     * @return performanceFeeShares Shares that would be minted to the performance fee receiver.
     * @return protocolFeeShares Shares that would be minted to the protocol fee receiver.
     */
    function getAccrueInterest()
        external
        view
        returns (
            uint256 newTotalAssets,
            uint256 managementFeeShares,
            uint256 performanceFeeShares,
            uint256 protocolFeeShares
        );

    /**
     * @notice Get assets available for instant withdrawal from free and deallocatable assets.
     * @return assets Withdrawable asset amount.
     * @dev This function is non-veiw since it simulates deallocation internally.
     */
    function withdrawable() external returns (uint256 assets);

    /**
     * @notice Get shares available for instant redemption from free and deallocatable assets.
     * @return shares Redeemable shares amount.
     * @dev This function is non-veiw since it simulates deallocation internally.
     */
    function redeemable() external returns (uint256 shares);

    /**
     * @notice Get liquid assets currently held by the vault.
     * @return assets Liquid asset balance.
     */
    function freeAssets() external view returns (uint256 assets);

    /**
     * @notice Accrue management, performance, and protocol fees using the latest known total assets.
     * @return managementFeeShares Shares minted to the management fee receiver.
     * @return performanceFeeShares Shares minted to the performance fee receiver.
     * @return protocolFeeShares Shares minted to the protocol fee receiver.
     */
    function accrueInterest()
        external
        returns (uint256 managementFeeShares, uint256 performanceFeeShares, uint256 protocolFeeShares);

    /**
     * @notice Pull liquid assets from the vault to a receiver.
     * @param assets Amount of assets to pull.
     * @param receiver Account that receives the assets.
     * @dev Only the configured delegator can call this function.
     */
    function pull(uint256 assets, address receiver) external;

    /**
     * @notice Push liquid assets from an owner into the vault.
     * @param assets Amount of assets to push.
     * @param owner Account that supplies the assets.
     * @dev Only the configured delegator can call this function.
     */
    function push(uint256 assets, address owner) external;

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

    /**
     * @notice Set the management fee and receiver.
     * @param fee Management fee per second scaled by MAX_FEE.
     * @param receiver Management fee receiver.
     * @dev Only a MANAGEMENT_FEE_ROLE holder can call this function.
     */
    function setManagementFee(uint96 fee, address receiver) external;

    /**
     * @notice Set the performance fee and receiver.
     * @param fee Performance fee scaled by MAX_FEE.
     * @param receiver Performance fee receiver.
     * @dev Only a PERFORMANCE_FEE_ROLE holder can call this function.
     */
    function setPerformanceFee(uint96 fee, address receiver) external;

    /**
     * @notice Set the delegator.
     * @param delegator Vault's delegator.
     * @dev Can be set only once.
     */
    function setDelegator(address delegator) external;

    /**
     * @notice Compatibility hook for VaultConfigurator slasher wiring.
     * @param slasher Ignored slasher address.
     */
    function setSlasher(address slasher) external;
}
