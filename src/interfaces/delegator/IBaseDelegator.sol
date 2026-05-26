// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IEntity} from "../common/IEntity.sol";

/**
 * @title IBaseDelegator
 * @notice Interface for the BaseDelegator contract.
 */
interface IBaseDelegator is IEntity {
    error AlreadySet();
    error InsufficientHookGas();
    error NotNetwork();
    error NotSlasher();
    error NotVault();

    /**
     * @notice Base parameters needed for delegators' deployment.
     * @param defaultAdminRoleHolder Address of the initial DEFAULT_ADMIN_ROLE holder.
     * @param hook Address of the hook contract.
     * @param hookSetRoleHolder Address of the initial HOOK_SET_ROLE holder.
     */
    struct BaseParams {
        address defaultAdminRoleHolder;
        address hook;
        address hookSetRoleHolder;
    }

    /**
     * @notice Base hints for a stake.
     * @param operatorVaultOptInHint Hint for the operator-vault opt-in.
     * @param operatorNetworkOptInHint Hint for the operator-network opt-in.
     */
    struct StakeBaseHints {
        bytes operatorVaultOptInHint;
        bytes operatorNetworkOptInHint;
    }

    /**
     * @notice Emitted when a subnetwork's maximum limit is set.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param amount New maximum subnetwork's limit (how much stake the subnetwork is ready to get).
     */
    event SetMaxNetworkLimit(bytes32 indexed subnetwork, uint256 amount);

    /**
     * @notice Emitted when a slash happens.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Amount of the collateral to be slashed.
     * @param captureTimestamp Time point when the stake was captured.
     */
    event OnSlash(bytes32 indexed subnetwork, address indexed operator, uint256 amount, uint48 captureTimestamp);

    /**
     * @notice Emitted when a hook is set.
     * @param hook Address of the hook.
     */
    event SetHook(address indexed hook);

    /**
     * @notice Get a gas limit for the hook.
     * @return Value Of the hook gas limit.
     */
    function HOOK_GAS_LIMIT() external view returns (uint256);

    /**
     * @notice Get a reserve gas between the gas limit check and the hook's execution.
     * @return Value Of the reserve gas.
     */
    function HOOK_RESERVE() external view returns (uint256);

    /**
     * @notice Get a hook setter's role.
     * @return Identifier Of the hook setter role.
     */
    function HOOK_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the network registry's address.
     * @return Address Of the network registry.
     */
    function NETWORK_REGISTRY() external view returns (address);

    /**
     * @notice Get the vault factory's address.
     * @return Address Of the vault factory.
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get the operator-vault opt-in service's address.
     * @return Address Of the operator-vault opt-in service.
     */
    function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get the operator-network opt-in service's address.
     * @return Address Of the operator-network opt-in service.
     */
    function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);

    /**
     * @notice Get the vault's address.
     * @return Address Of the vault.
     */
    function vault() external view returns (address);

    /**
     * @notice Get the hook's address.
     * @return Address Of the hook.
     * @dev The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function hook() external view returns (address);

    /**
     * @notice Get a particular subnetwork's maximum limit
     * (meaning the subnetwork is not ready to get more as a stake).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Maximum Limit of the subnetwork.
     */
    function maxNetworkLimit(bytes32 subnetwork) external view returns (uint256);

    /**
     * @notice Get a version of the delegator (different versions mean different interfaces).
     * @return Version Of the delegator.
     * @dev Must return 1 for this one.
     */
    function VERSION() external view returns (uint64);

    /**
     * @notice Get a stake that a given subnetwork could be able to slash for a certain operator at a given timestamp
     * until the end of the consequent epoch using hints (if no cross-slashing and no slashings by the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param timestamp Time point to capture the stake at.
     * @param hints Hints for the checkpoints' indexes.
     * @return Slashable Stake at the given timestamp until the end of the consequent epoch.
     * @dev Warning: it is not safe to use timestamp >= current one for the stake capturing, as it can change later.
     */
    function stakeAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint256);

    /**
     * @notice Get a stake that a given subnetwork will be able to slash
     * for a certain operator until the end of the next epoch (if no cross-slashing and no slashings by the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @return Slashable Stake until the end of the next epoch.
     * @dev Warning: this function is not safe to use for stake capturing, as it can change by the end of the block.
     */
    function stake(bytes32 subnetwork, address operator) external view returns (uint256);

    /**
     * @notice Set a maximum limit for a subnetwork (how much stake the subnetwork is ready to get).
     * @param identifier Identifier of the subnetwork.
     * @param amount New maximum subnetwork's limit.
     * @dev Only a network can call this function.
     */
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;

    /**
     * @notice Set a new hook.
     * @param hook Address of the hook.
     * @dev Only a HOOK_SET_ROLE holder can call this function.
     * The hook can have arbitrary logic under certain functions, however, it doesn't affect the stake guarantees.
     */
    function setHook(address hook) external;

    /**
     * @notice Called when a slash happens.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param operator Address of the operator.
     * @param amount Amount of the collateral slashed.
     * @param captureTimestamp Time point when the stake was captured.
     * @param data Some additional data.
     * @dev Only the vault's slasher can call this function.
     */
    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes calldata data)
        external;
}
