// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseDelegator} from "./IBaseDelegator.sol";

uint64 constant OPERATOR_SPECIFIC_DELEGATOR_TYPE = 2;

/**
 * @title IOperatorSpecificDelegator
 * @notice Interface for the OperatorSpecificDelegator contract.
 */
interface IOperatorSpecificDelegator is IBaseDelegator {
    error DuplicateRoleHolder();
    error ExceedsMaxNetworkLimit();
    error MissingRoleHolders();
    error NotOperator();
    error ZeroAddressRoleHolder();

    /**
     * @notice Hints for a stake.
     * @param baseHints Base hints.
     * @param activeStakeHint Hint for the active stake checkpoint.
     * @param networkLimitHint Hint for the subnetwork limit checkpoint.
     */
    struct StakeHints {
        bytes baseHints;
        bytes activeStakeHint;
        bytes networkLimitHint;
    }

    /**
     * @notice Initial parameters needed for an operator-specific delegator deployment.
     * @param baseParams Base parameters for delegators' deployment.
     * @param networkLimitSetRoleHolders Array of addresses of the initial NETWORK_LIMIT_SET_ROLE holders.
     * @param operator Address of the single operator.
     */
    struct InitParams {
        IBaseDelegator.BaseParams baseParams;
        address[] networkLimitSetRoleHolders;
        address operator;
    }

    /**
     * @notice Emitted when a subnetwork's limit is set.
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param amount New subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).
     */
    event SetNetworkLimit(bytes32 indexed subnetwork, uint256 amount);

    /**
     * @notice Get a subnetwork limit setter's role.
     * @return Identifier Of the subnetwork limit setter role.
     */
    function NETWORK_LIMIT_SET_ROLE() external view returns (bytes32);

    /**
     * @notice Get the operator registry's address.
     * @return Address Of the operator registry.
     */
    function OPERATOR_REGISTRY() external view returns (address);

    /**
     * @notice Get an operator managing the vault's funds.
     * @return Address Of the operator.
     */
    function operator() external view returns (address);

    /**
     * @notice Get a subnetwork's limit at a given timestamp using a hint
     * (how much stake the vault curator is ready to give to the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param timestamp Time point to get the subnetwork limit at.
     * @param hint Hint for checkpoint index.
     * @return Limit Of the subnetwork at the given timestamp.
     */
    function networkLimitAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (uint256);

    /**
     * @notice Get a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @return Limit Of the subnetwork.
     */
    function networkLimit(bytes32 subnetwork) external view returns (uint256);

    /**
     * @notice Set a subnetwork's limit (how much stake the vault curator is ready to give to the subnetwork).
     * @param subnetwork Full identifier of the subnetwork (address of the network concatenated with the uint96 identifier).
     * @param amount New limit of the subnetwork.
     * @dev Only a NETWORK_LIMIT_SET_ROLE holder can call this function.
     */
    function setNetworkLimit(bytes32 subnetwork, uint256 amount) external;
}
